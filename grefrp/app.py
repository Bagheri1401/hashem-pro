"""Private admin UI; bind to 127.0.0.1 and reach it using SSH forwarding."""
import hashlib
import hmac
import os
import secrets
from pathlib import Path
from urllib.parse import urlencode

from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, RedirectResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.concurrency import run_in_threadpool
from starlette.middleware.sessions import SessionMiddleware

from . import core

APP_DIR = Path(__file__).resolve().parents[1]
secret = os.environ.get('SESSION_SECRET', '')
if len(secret) < 40:
    raise RuntimeError('SESSION_SECRET is missing or too short (minimum 40 chars)')
app = FastAPI(title='GRE + FRP Tunnel Manager', docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(SessionMiddleware, secret_key=secret,
                   same_site='strict', https_only=os.environ.get('SESSION_SECURE', '0') == '1',
                   max_age=3600)
app.mount('/static', StaticFiles(directory=str(APP_DIR/'static')), name='static')
templates = Jinja2Templates(directory=str(APP_DIR/'templates'))
core.init_db()


def password_ok(password):
    saved = os.environ.get('ADMIN_PASSWORD_HASH','')
    parts = saved.split('$')
    if len(parts) != 3 or parts[0] != 'pbkdf2_sha256':
        return False
    try:
        salt = bytes.fromhex(parts[1]); expected = bytes.fromhex(parts[2])
        actual = hashlib.pbkdf2_hmac('sha256',password.encode(),salt,500_000)
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def logged_in(request):
    return request.session.get('admin') is True


def csrf_token(request):
    if not request.session.get('csrf'):
        request.session['csrf'] = secrets.token_urlsafe(28)
    return request.session['csrf']


def csrf_check(request, submitted):
    return bool(logged_in(request) and submitted and
                hmac.compare_digest(request.session.get('csrf',''), submitted))


def redirect(path, message=None, error=None):
    vals={}
    if message: vals['message']=message
    if error: vals['error']=str(error)[:350]
    return RedirectResponse(path+('?' + urlencode(vals) if vals else ''),status_code=303)


def require_login(request):
    if not logged_in(request):
        return redirect('/login')
    return None


def render(request, template, **params):
    context={'request':request, 'csrf': csrf_token(request),
             'message':request.query_params.get('message',''),
             'error':request.query_params.get('error',''), **params}
    return templates.TemplateResponse(request, template, context)


@app.get('/login', response_class=HTMLResponse)
async def login_page(request:Request):
    if logged_in(request): return redirect('/')
    return render(request,'login.html')


@app.post('/login')
async def login(request:Request, username:str=Form(...), password:str=Form(...), csrf:str=Form(...)):
    if not hmac.compare_digest(request.session.get('csrf',''),csrf):
        return redirect('/login',error='نشست نامعتبر است؛ صفحه را بازخوانی کنید.')
    if not (hmac.compare_digest(username,os.getenv('ADMIN_USERNAME','admin')) and password_ok(password)):
        return redirect('/login',error='نام کاربری یا رمز عبور نادرست است.')
    request.session.clear()
    request.session['admin']=True
    csrf_token(request)
    return redirect('/')


@app.post('/logout')
async def logout(request:Request,csrf:str=Form(...)):
    if not csrf_check(request,csrf): return PlainTextResponse('Forbidden',status_code=403)
    request.session.clear()
    return redirect('/login')


@app.get('/', response_class=HTMLResponse)
async def dashboard(request:Request):
    auth=require_login(request)
    if auth: return auth
    nodes=core.list_nodes()
    for n in nodes:
        try:
            n['gre']=core.execute(['systemctl','is-active',f'grefrp-gre-gf{n["id"]}.service'],check=False).stdout.strip() or 'unknown'
            n['frps']=core.execute(['systemctl','is-active',f'grefrp-frps-gf{n["id"]}.service'],check=False).stdout.strip() or 'unknown'
        except core.DeployError:
            n['gre']=n['frps']='unknown'
    return render(request,'index.html',nodes=nodes)


@app.post('/nodes')
async def add_node(request:Request, csrf:str=Form(...), name:str=Form(...),
                   iran_public_ip:str=Form(...), foreign_public_ip:str=Form(...),
                   ssh_port:int=Form(22),mtu:int=Form(1400)):
    if not csrf_check(request,csrf): return PlainTextResponse('Forbidden',status_code=403)
    try:
        node_id=core.add_node(name,iran_public_ip,foreign_public_ip,ssh_port,mtu)
    except (ValueError,core.DeployError) as exc:
        return redirect('/',error=exc)
    return redirect(f'/nodes/{node_id}',message='سرور ثبت شد؛ اکنون کلید SSH و میزبان را آماده کنید و «اعمال تنظیمات» را بزنید.')


@app.get('/nodes/{node_id}',response_class=HTMLResponse)
async def node_detail(request:Request,node_id:int):
    auth=require_login(request)
    if auth: return auth
    try:
        node=core.get_node(node_id)
    except ValueError:
        return redirect('/',error='سرور پیدا نشد.')
    forwards=core.get_forwards(node_id)
    return render(request,'node.html',node=node,forwards=forwards,
                  tunnel_iran=core.iran_tunnel_ip(node),tunnel_foreign=core.foreign_tunnel_ip(node))


@app.post('/nodes/{node_id}/forwards')
async def add_rule(request:Request,node_id:int,csrf:str=Form(...),name:str=Form(...),
                   protocol:str=Form(...),iran_port:int=Form(...),foreign_port:int=Form(...)):
    if not csrf_check(request,csrf): return PlainTextResponse('Forbidden',status_code=403)
    try:
        core.add_forward(node_id,name,protocol,iran_port,foreign_port)
        return redirect(f'/nodes/{node_id}',message='قانون ثبت شد. برای اجرا «اعمال تنظیمات» را بزنید.')
    except (ValueError,core.DeployError) as exc:
        return redirect(f'/nodes/{node_id}',error=exc)


@app.post('/nodes/{node_id}/forwards/{rule_id}/delete')
async def delete_rule(request:Request,node_id:int,rule_id:int,csrf:str=Form(...)):
    if not csrf_check(request,csrf): return PlainTextResponse('Forbidden',status_code=403)
    core.remove_forward(node_id,rule_id)
    return redirect(f'/nodes/{node_id}',message='قانون حذف شد. برای اعمال حذف روی سرورها «اعمال تنظیمات» را بزنید.')


@app.post('/nodes/{node_id}/{action}')
async def manage_node(request:Request,node_id:int,action:str,csrf:str=Form(...)):
    if not csrf_check(request,csrf): return PlainTextResponse('Forbidden',status_code=403)
    if action not in ('apply','start','stop','delete'):
        return PlainTextResponse('Not Found',status_code=404)
    operations={'apply':core.deploy,'start':core.start,'stop':core.stop,'delete':core.delete}
    try:
        message=await run_in_threadpool(operations[action],node_id)
        return redirect('/' if action=='delete' else f'/nodes/{node_id}',message=message)
    except (ValueError,core.DeployError) as exc:
        return redirect(f'/nodes/{node_id}',error=exc)


@app.post('/nodes/{node_id}/check')
async def check_node(request:Request,node_id:int,csrf:str=Form(...)):
    if not csrf_check(request,csrf): return PlainTextResponse('Forbidden',status_code=403)
    try:
        status=await run_in_threadpool(core.local_status,node_id)
        return render(request,'status.html',node=core.get_node(node_id),status=status)
    except (core.DeployError,ValueError) as exc:
        return redirect(f'/nodes/{node_id}',error=exc)


@app.get('/nodes/{node_id}/logs',response_class=HTMLResponse)
async def log_page(request:Request,node_id:int):
    auth=require_login(request)
    if auth: return auth
    try:
        logs=await run_in_threadpool(core.logs,node_id)
        return render(request,'logs.html',node=core.get_node(node_id),logs=logs)
    except (core.DeployError,ValueError) as exc:
        return redirect(f'/nodes/{node_id}',error=exc)

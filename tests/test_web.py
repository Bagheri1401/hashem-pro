import hashlib
import os
import secrets
from fastapi.testclient import TestClient


def test_login_and_create_node(tmp_path,monkeypatch):
    monkeypatch.setenv('SESSION_SECRET','A'*70)
    monkeypatch.setenv('ADMIN_USERNAME','admin')
    pwd='correct-horse-battery-staple'
    salt=b'1234567890123456'
    h=hashlib.pbkdf2_hmac('sha256',pwd.encode(),salt,500_000)
    monkeypatch.setenv('ADMIN_PASSWORD_HASH',f'pbkdf2_sha256${salt.hex()}${h.hex()}')
    monkeypatch.setenv('GRE_FRP_DATA',str(tmp_path))
    from grefrp import core
    monkeypatch.setattr(core,'BASE',tmp_path)
    monkeypatch.setattr(core,'DB',tmp_path/'web.db')
    from grefrp.app import app
    core.init_db()
    client=TestClient(app)
    res=client.get('/')
    assert res.url.path=='/login'
    token=client.get('/login').text.split('name="csrf" value="')[1].split('"')[0]
    res=client.post('/login',data={'username':'admin','password':pwd,'csrf':token},follow_redirects=True)
    assert res.status_code==200 and 'مدیریت تانل‌ها' in res.text
    token=res.text.split('name="csrf" value="')[1].split('"')[0]
    denied=client.post('/nodes',data={'csrf':'bad','name':'France','iran_public_ip':'5.6.7.8','foreign_public_ip':'1.2.3.4'})
    assert denied.status_code==403
    okay=client.post('/nodes',data={'csrf':token,'name':'France','iran_public_ip':'5.6.7.8','foreign_public_ip':'1.2.3.4','ssh_port':22,'mtu':1400},follow_redirects=True)
    assert okay.status_code==200 and 'France' in okay.text

"""Validated, deterministic GRE and frp deployment plans.

No remote commands run on import; use a restricted service account and SSH
host-key pinning. This tool never changes the default IP route.
"""
import base64
import ipaddress
import os
import re
import secrets
import shlex
import sqlite3
import subprocess
import threading
from contextlib import contextmanager
from pathlib import Path

BASE = Path(os.getenv("GRE_FRP_DATA", "/var/lib/grefrp"))
ETC = Path(os.getenv("GRE_FRP_ETC", "/etc/grefrp"))
DB = BASE / "state.db"
SSH_KEY = ETC / "id_ed25519"
SSH_HOSTS = ETC / "known_hosts"
NODE_LOCK = threading.RLock()
NAME_RE = re.compile(r"^[\w\- .]{2,48}$", re.UNICODE)
SERVICE_RE = re.compile(r"^[\w\- .]{2,48}$", re.UNICODE)

class DeployError(Exception):
    pass


@contextmanager
def db_connect():
    BASE.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DB, timeout=30)
    try:
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA journal_mode=WAL")
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def init_db():
    with db_connect() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS nodes (
          id INTEGER PRIMARY KEY CHECK(id BETWEEN 1 AND 250),
          name TEXT NOT NULL,
          iran_public_ip TEXT NOT NULL,
          foreign_public_ip TEXT NOT NULL UNIQUE,
          ssh_port INTEGER NOT NULL,
          mtu INTEGER NOT NULL,
          frp_port INTEGER NOT NULL UNIQUE,
          token TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS forwards (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          node_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          protocol TEXT NOT NULL CHECK(protocol IN ('tcp','udp')),
          iran_port INTEGER NOT NULL,
          foreign_port INTEGER NOT NULL,
          UNIQUE(protocol,iran_port)
        );
        """)


def ipv4(value):
    try:
        address = ipaddress.IPv4Address(value.strip())
    except (ValueError, AttributeError) as exc:
        raise ValueError("آدرس IP باید IPv4 معتبر باشد.") from exc
    if address.is_multicast or address.is_loopback or address.is_unspecified or address.is_link_local:
        raise ValueError("آدرس عمومی سرور نامعتبر است.")
    return str(address)


def port(value, min_port=1):
    try:
        num = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("شماره پورت معتبر نیست.") from exc
    if not min_port <= num <= 65535:
        raise ValueError(f"پورت باید بین {min_port} تا 65535 باشد.")
    return num


def clean_name(name, validator=NAME_RE):
    name = str(name).strip()
    if not validator.fullmatch(name):
        raise ValueError("نام باید ۲ تا ۴۸ حرف و بدون کاراکتر خاص باشد.")
    return name


def add_node(name, iran_ip, foreign_ip, ssh_port=22, mtu=1400):
    name = clean_name(name)
    iran_ip, foreign_ip = ipv4(iran_ip), ipv4(foreign_ip)
    if iran_ip == foreign_ip:
        raise ValueError("آدرس عمومی سرور ایران و خارج نباید یکسان باشد.")
    ssh_port = port(ssh_port)
    mtu = int(mtu)
    if not 1280 <= mtu <= 1476:
        raise ValueError("MTU مجاز برای این پروفایل ۱۲۸۰ تا ۱۴۷۶ است.")
    with NODE_LOCK, db_connect() as db:
        ids = {x[0] for x in db.execute("SELECT id FROM nodes")}
        node_id = next((i for i in range(1,251) if i not in ids), None)
        if not node_id:
            raise ValueError("حداکثر ۲۵۰ سرور خارج پشتیبانی می‌شود.")
        # 7200 + id is dedicated to private control channel for this node.
        control_port = 7200 + node_id
        try:
            db.execute("INSERT INTO nodes (id,name,iran_public_ip,foreign_public_ip,ssh_port,mtu,frp_port,token) VALUES (?,?,?,?,?,?,?,?)",
                 (node_id,name,iran_ip,foreign_ip,ssh_port,mtu,control_port,secrets.token_urlsafe(36)))
            db.commit()
        except sqlite3.IntegrityError as exc:
            raise ValueError("این IP قبلاً ثبت شده است.") from exc
    return node_id


def add_forward(node_id, name, protocol, iran_port, foreign_port):
    name = clean_name(name, SERVICE_RE)
    protocol = str(protocol).lower().strip()
    if protocol not in ("tcp", "udp"):
        raise ValueError("پروتکل باید TCP یا UDP باشد.")
    iran_port = port(iran_port, 1024)
    foreign_port = port(foreign_port)
    if iran_port in range(7201, 7451) or iran_port == 8765:
        raise ValueError("این پورت برای مدیریت رزرو شده است.")
    with NODE_LOCK, db_connect() as db:
        try:
            db.execute("INSERT INTO forwards (node_id,name,protocol,iran_port,foreign_port) VALUES (?,?,?,?,?)",
                       (node_id,name,protocol,iran_port,foreign_port))
            db.commit()
        except sqlite3.IntegrityError as exc:
            raise ValueError("این پورت روی ایران قبلاً ثبت شده یا سرور وجود ندارد.") from exc


def get_node(node_id):
    with db_connect() as db:
        node = db.execute("SELECT * FROM nodes WHERE id=?", (node_id,)).fetchone()
        if node is None:
            raise ValueError("سرور پیدا نشد.")
        return dict(node)


def list_nodes():
    with db_connect() as db:
        return [dict(row) for row in db.execute("SELECT * FROM nodes ORDER BY id")]


def get_forwards(node_id):
    with db_connect() as db:
        return [dict(row) for row in db.execute("SELECT * FROM forwards WHERE node_id=? ORDER BY id", (node_id,))]


def remove_forward(node_id, fwd_id):
    with NODE_LOCK, db_connect() as db:
        db.execute("DELETE FROM forwards WHERE id=? AND node_id=?", (fwd_id,node_id))
        db.commit()


def iface(node):
    return f"gf{node['id']}"


def iran_tunnel_ip(node):
    return f"10.233.{node['id']}.1"


def foreign_tunnel_ip(node):
    return f"10.233.{node['id']}.2"


def shell_quote(value):
    return shlex.quote(str(value))


def config_server(node, forwards):
    """Per-node FRPS instances avoid sharing one token across foreign nodes."""
    content = [
       f'bindAddr = "{iran_tunnel_ip(node)}"',
       f'bindPort = {node["frp_port"]}',
       'proxyBindAddr = "0.0.0.0"',
       'auth.method = "token"',
       f'auth.token = "{node["token"]}"',
       'transport.tls.force = true',
       'log.level = "info"',
    ]
    # Restrict remote registrations to assigned public ports.
    if forwards:
        for rule in forwards:
            content.extend(['[[allowPorts]]', f'start = {rule["iran_port"]}', f'end = {rule["iran_port"]}'])
    else:
        # Without published services, reserve a high unused port; do not permit any useful registration.
        content.extend(['[[allowPorts]]', 'start = 65535', 'end = 65535'])
    return "\n".join(content) + "\n"


def config_client(node, forwards):
    content = [
       f'serverAddr = "{iran_tunnel_ip(node)}"',
       f'serverPort = {node["frp_port"]}',
       'loginFailExit = false',
       'auth.method = "token"',
       f'auth.token = "{node["token"]}"',
       'transport.tls.enable = true',
       'log.level = "info"',
    ]
    for rule in forwards:
        content.extend(['[[proxies]]', f'name = "gf{node["id"]}-p{rule["id"]}"',
          f'type = "{rule["protocol"]}"', 'localIP = "127.0.0.1"',
          f'localPort = {rule["foreign_port"]}', f'remotePort = {rule["iran_port"]}'])
    return "\n".join(content) + "\n"


def gre_up_script(node, role):
    """Creates exactly one GRE interface and no changes to system default route."""
    if role not in ('iran','foreign'):
        raise ValueError("Invalid role")
    local, remote = ((node['iran_public_ip'],node['foreign_public_ip']) if role=='iran'
                     else (node['foreign_public_ip'],node['iran_public_ip']))
    tunnel = iran_tunnel_ip(node) if role=='iran' else foreign_tunnel_ip(node)
    dev = iface(node)
    return f'''#!/bin/sh
set -eu
modprobe ip_gre || true
if ! ip link show {dev} >/dev/null 2>&1; then
  ip tunnel add {dev} mode gre local {local} remote {remote} ttl 255 key {node['id']}
fi
ip addr replace {tunnel}/30 dev {dev}
ip link set dev {dev} mtu {node['mtu']} up
'''


def gre_down_script(node):
    return f'#!/bin/sh\nset -eu\nip link del {iface(node)} 2>/dev/null || true\n'


def gre_unit(node):
    dev=iface(node)
    return f'''[Unit]
Description=GRE interface for {dev}
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh /etc/grefrp/nodes/{dev}-up.sh
ExecStop=/bin/sh /etc/grefrp/nodes/{dev}-down.sh
TimeoutStartSec=20
[Install]
WantedBy=multi-user.target
'''


def frp_unit(node, role):
    dev=iface(node)
    binary='frps' if role=='iran' else 'frpc'
    return f'''[Unit]
Description={binary} over GRE {dev}
Wants=network-online.target
Requires=grefrp-gre-{dev}.service
After=network-online.target grefrp-gre-{dev}.service
[Service]
Type=simple
ExecStart=/usr/local/bin/{binary} -c /etc/grefrp/nodes/{dev}-{binary}.toml
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log
[Install]
WantedBy=multi-user.target
'''


def execute(args, *, input_data=None, timeout=30, check=True):
    try:
        result = subprocess.run(args, input=input_data, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise DeployError(f"فرمان اجرا نشد: {str(exc)[:250]}") from exc
    if check and result.returncode != 0:
        raise DeployError((result.stderr or result.stdout or 'command failed').strip()[-1400:])
    return result


def ssh(node, script, timeout=60):
    if not SSH_KEY.is_file() or not SSH_HOSTS.is_file():
        raise DeployError("کلید SSH یا فایل known_hosts آماده نیست. راهنمای README را ببینید.")
    args = ["ssh", "-F", "/dev/null", "-o", "BatchMode=yes",
      "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile={SSH_HOSTS}",
      "-o", "ConnectTimeout=7", "-o", "LogLevel=ERROR",
      "-i", str(SSH_KEY), "-p", str(node['ssh_port']),
      f"root@{node['foreign_public_ip']}", "bash -s"]
    return execute(args, input_data=script, timeout=timeout)


def write_cmd(path, data, mode='600'):
    b64=base64.b64encode(data.encode()).decode()
    return f"printf '%s' {shell_quote(b64)} | base64 -d > {shell_quote(path)}\nchmod {mode} {shell_quote(path)}\n"


def paths(node):
    dev=iface(node)
    return {
      'up': f'/etc/grefrp/nodes/{dev}-up.sh',
      'down': f'/etc/grefrp/nodes/{dev}-down.sh',
      'gre_unit': f'/etc/systemd/system/grefrp-gre-{dev}.service',
      'frps': f'/etc/grefrp/nodes/{dev}-frps.toml',
      'frpc': f'/etc/grefrp/nodes/{dev}-frpc.toml',
      'frps_unit':f'/etc/systemd/system/grefrp-frps-{dev}.service',
      'frpc_unit':f'/etc/systemd/system/grefrp-frpc-{dev}.service',
    }


def local_write(path, text, mode=0o600):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_name(target.name + '.tmp')
    with open(temp, 'w', encoding='utf-8') as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.chmod(temp, mode)
    os.replace(temp, target)


def preflight(node):
    execute(['sh','-c','command -v ip >/dev/null && command -v systemctl >/dev/null && test -x /usr/local/bin/frps'])
    ssh(node, 'set -eu\ncommand -v ip\ncommand -v systemctl\ntest -x /usr/local/bin/frpc\necho PRECHECK_OK\n')


def make_remote_files(node, forwards):
    p=paths(node)
    commands=['set -eu','install -d -m 700 /etc/grefrp/nodes']
    commands.append(write_cmd(p['up'], gre_up_script(node,'foreign'), '700'))
    commands.append(write_cmd(p['down'], gre_down_script(node), '700'))
    commands.append(write_cmd(p['gre_unit'], gre_unit(node), '644'))
    commands.append(write_cmd(p['frpc'], config_client(node,forwards), '600'))
    commands.append(write_cmd(p['frpc_unit'], frp_unit(node,'foreign'), '644'))
    commands.append(f"/usr/local/bin/frpc verify -c {shell_quote(p['frpc'])}")
    commands.append('systemctl daemon-reload')
    return '\n'.join(commands)+'\n'


def write_local_files(node, forwards):
    p=paths(node)
    local_write(p['up'], gre_up_script(node,'iran'), 0o700)
    local_write(p['down'], gre_down_script(node), 0o700)
    local_write(p['gre_unit'], gre_unit(node), 0o644)
    local_write(p['frps'], config_server(node,forwards), 0o600)
    local_write(p['frps_unit'], frp_unit(node,'iran'), 0o644)
    execute(['/usr/local/bin/frps','verify','-c',p['frps']])
    execute(['systemctl','daemon-reload'])


def deploy(node_id):
    with NODE_LOCK:
        node=get_node(node_id)
        forwards=get_forwards(node_id)
        preflight(node)
        ssh(node, make_remote_files(node, forwards))
        write_local_files(node, forwards)
        dev=iface(node)
        # Create both GRE interfaces first, then start FRPS and FRPC.
        ssh(node, f'set -eu\nsystemctl enable --now grefrp-gre-{dev}.service\n')
        execute(['systemctl','enable','--now',f'grefrp-gre-{dev}.service'])
        # A restart ensures edited service mapping/config becomes live.
        execute(['systemctl','enable',f'grefrp-frps-{dev}.service'])
        execute(['systemctl','restart',f'grefrp-frps-{dev}.service'])
        ssh(node, f'set -eu\nsystemctl enable grefrp-frpc-{dev}.service\nsystemctl restart grefrp-frpc-{dev}.service\n')
        return 'تنظیمات ارسال و سرویس‌ها راه‌اندازی شدند. وضعیت تونل را بررسی کنید.'


def start(node_id):
    with NODE_LOCK:
        node=get_node(node_id); dev=iface(node)
        ssh(node, f'set -eu\nsystemctl start grefrp-gre-{dev}.service\n')
        execute(['systemctl','start',f'grefrp-gre-{dev}.service'])
        execute(['systemctl','start',f'grefrp-frps-{dev}.service'])
        ssh(node, f'set -eu\nsystemctl start grefrp-frpc-{dev}.service\n')
        return 'سرویس‌ها روشن شدند.'


def stop(node_id):
    with NODE_LOCK:
        node=get_node(node_id); dev=iface(node)
        ssh(node, f'systemctl stop grefrp-frpc-{dev}.service grefrp-gre-{dev}.service || true\n')
        execute(['systemctl','stop',f'grefrp-frps-{dev}.service',f'grefrp-gre-{dev}.service'])
        return 'تونل در هر دو سرور متوقف شد.'


def delete(node_id):
    with NODE_LOCK:
        node=get_node(node_id); p=paths(node); dev=iface(node)
        remote = f'''set -eu
systemctl disable --now grefrp-frpc-{dev}.service grefrp-gre-{dev}.service || true
rm -f {shell_quote(p['up'])} {shell_quote(p['down'])} {shell_quote(p['gre_unit'])} {shell_quote(p['frpc'])} {shell_quote(p['frpc_unit'])}
systemctl daemon-reload
'''
        # Do not delete registry if remote side cannot be cleaned.
        ssh(node,remote)
        execute(['systemctl','disable','--now',f'grefrp-frps-{dev}.service',f'grefrp-gre-{dev}.service'],check=False)
        for key in ('up','down','gre_unit','frps','frps_unit'):
            Path(p[key]).unlink(missing_ok=True)
        execute(['systemctl','daemon-reload'])
        with db_connect() as db:
            db.execute('DELETE FROM nodes WHERE id=?',(node_id,))
            db.commit()
        return 'سرور و فایل‌های مدیریتی آن حذف شدند.'


def local_status(node_id):
    node=get_node(node_id); dev=iface(node)
    checks={}
    for unit in (f'grefrp-gre-{dev}.service',f'grefrp-frps-{dev}.service'):
        result=execute(['systemctl','is-active',unit],check=False)
        checks[unit] = result.stdout.strip() or 'unknown'
    ping = execute(['ping','-c','1','-W','2',foreign_tunnel_ip(node)],timeout=5,check=False)
    checks['ping_remote_GRE'] = 'ok' if ping.returncode == 0 else 'failed'
    try:
        out=ssh(node, f'systemctl is-active grefrp-frpc-{dev}.service || true\n',timeout=14)
        checks['remote_frpc'] = out.stdout.strip() or 'unknown'
    except DeployError as exc:
        checks['remote_frpc'] = f'SSH error: {exc}'
    return checks


def logs(node_id):
    node=get_node(node_id); dev=iface(node)
    return execute(['journalctl','-u',f'grefrp-frps-{dev}.service','-n','40','--no-pager','--output=short-iso'],check=False).stdout[-13000:]

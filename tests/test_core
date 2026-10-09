try:
    import tomllib
except ImportError:  # Ubuntu 22.04 / Python 3.10
    import tomli as tomllib
import pytest
from grefrp import core

@pytest.fixture(autouse=True)
def scratch(tmp_path,monkeypatch):
    monkeypatch.setattr(core,'BASE',tmp_path)
    monkeypatch.setattr(core,'DB',tmp_path/'test.db')
    core.init_db()


def test_many_foreign_nodes_and_distinct_tokens():
    a=core.add_node('Germany 1','5.6.7.8','1.2.3.4')
    b=core.add_node('Turkey 2','5.6.7.8','1.2.3.5')
    assert a == 1 and b == 2
    n1,n2=core.get_node(a),core.get_node(b)
    assert n1['token'] != n2['token']
    assert core.iran_tunnel_ip(n1)=='10.233.1.1'
    assert core.foreign_tunnel_ip(n2)=='10.233.2.2'
    assert core.iface(n2)=='gf2'


def test_frp_toml_forwarding_and_access_controls():
    idx=core.add_node('Amsterdam','5.6.7.8','1.2.3.4')
    core.add_forward(idx,'My service','tcp',15001,8080)
    core.add_forward(idx,'My DNS','udp',15002,5353)
    n, rules=core.get_node(idx),core.get_forwards(idx)
    s=tomllib.loads(core.config_server(n,rules))
    c=tomllib.loads(core.config_client(n,rules))
    assert s['bindAddr']=='10.233.1.1'
    assert s['proxyBindAddr']=='0.0.0.0'
    assert s['transport']['tls']['force'] is True
    assert s['auth']['token']==c['auth']['token']
    assert s['allowPorts']==[{'start':15001,'end':15001},{'start':15002,'end':15002}]
    assert c['serverAddr']=='10.233.1.1'
    assert c['transport']['tls']['enable'] is True
    assert [x['type'] for x in c['proxies']] == ['tcp','udp']
    assert c['proxies'][0]['localIP']=='127.0.0.1'


def test_gre_stays_on_fixed_public_interfaces_no_default_route():
    idx=core.add_node('Georgia','5.6.7.8','1.2.3.4')
    n=core.get_node(idx)
    iran=core.gre_up_script(n,'iran')
    foreign=core.gre_up_script(n,'foreign')
    assert 'local 5.6.7.8 remote 1.2.3.4' in iran
    assert 'local 1.2.3.4 remote 5.6.7.8' in foreign
    assert '10.233.1.1/30' in iran and '10.233.1.2/30' in foreign
    assert 'ip route' not in iran + foreign


def test_duplicates_and_bad_inputs_rejected():
    idx=core.add_node('France','5.6.7.8','1.2.3.4')
    core.add_forward(idx,'Service','tcp',15001,8080)
    with pytest.raises(ValueError): core.add_forward(idx,'Dup','tcp',15001,8081)
    with pytest.raises(ValueError): core.add_forward(idx,'Panel','tcp',8765,8081)
    with pytest.raises(ValueError): core.add_node('Duplicate IP','5.6.7.8','1.2.3.4')
    with pytest.raises(ValueError): core.add_node('Bad IP','not-an-ip','1.2.3.4')


def test_empty_server_ports_allowlist():
    idx=core.add_node('France','5.6.7.8','1.2.3.4')
    s=tomllib.loads(core.config_server(core.get_node(idx),[]))
    assert s['allowPorts']==[{'start':65535,'end':65535}]

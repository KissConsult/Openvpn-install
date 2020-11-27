#! /bin/bash

read -p 'Username: ' uservar
read -p 'Port: ' portvar
password=$(openssl rand -base64 32)
caPass=$(openssl rand -base64 32)

createUser () {

sudo useradd $uservar
sudo echo -e "$password\n$password" | (passwd --stdin $uservar)
echo $uservar\ > /etc/openvpn/pass.txt
echo $password >> /etc/openvpn/pass.txt
}

update () {
echo
echo "CentOS Update"
sudo yum -y update
echo
}

install () {
echo "Installing dependencies"
sudo yum -y install epel-release &&
sudo yum -y install openvpn &&
sudo yum -y install easy-rsa
wget -P /etc/openvpn/ https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
tar -xf /etc/openvpn/EasyRSA-unix-v3.0.6.tgz
mv /etc/openvpn/EasyRSA-v3.0.6/ /etc/openvpn/easy-rsa/; rm -f /etc/openvpn/EasyRSA-unix-v3.0.6.tgz

echo
}

easyrsa(){

echo "

set_var EASYRSA                 "$PWD"
set_var EASYRSA_PKI             "/etc/openvpn/easy-rsa/pki"
set_var EASYRSA_DN              "cn_only"
set_var EASYRSA_REQ_COUNTRY     "ID"
set_var EASYRSA_REQ_PROVINCE    "Province"
set_var EASYRSA_REQ_CITY        "City"
set_var EASYRSA_REQ_ORG         "CERTIFICATE AUTHORITY"
set_var EASYRSA_REQ_EMAIL       "openvpn@email.com"
set_var EASYRSA_REQ_OU          "EASY CA"
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_ALGO            rsa
set_var EASYRSA_CA_EXPIRE       7500
set_var EASYRSA_CERT_EXPIRE     365
set_var EASYRSA_NS_SUPPORT      "no"
set_var EASYRSA_NS_COMMENT      "HAKASE-LABS CERTIFICATE AUTHORITY"
set_var EASYRSA_EXT_DIR         "/etc/openvpn/easy-rsa/x509-types"
set_var EASYRSA_SSL_CONF        "/etc/openvpn/easy-rsa/openssl-easyrsa.cnf"
set_var EASYRSA_DIGEST          "sha256"

" > /etc/openvpn/easy-rsa/vars

chmod +x /etc/openvpn/easy-rsa/vars


echo " init pki"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  init-pki /etc/openvpn/easy-rsa/

echo " build-ca"

#/bin/bash /etc/openvpn/easy-rsa/easyrsa  build-ca
echo -e "12345\n12345\n" | /bin/bash /etc/openvpn/easy-rsa/easyrsa build-ca

echo " gen-req"

#/bin/bash /etc/openvpn/easy-rsa/easyrsa gen-req hakase-server nopass
echo -e "\nyes\n$caPass\n" | /bin/bash /etc/openvpn/easy-rsa/easyrsa gen-req hakase-server nopass

echo " sign-req"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  sign-req server hakase-server
echo " gen-dh"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  gen-dh
echo " gen-crl"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  gen-crl

cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/issued/hakase-server.crt /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/private/hakase-server.key /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/server/

echo "
port 1194
proto udp
dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/hakase-server.crt
key /etc/openvpn/server/hakase-server.key # This file should be kept secret
dh /etc/openvpn/server/dh.pem
crl-verify /etc/openvpn/server/crl.pem
server 10.5.0.0 255.255.255.0
verify-client-cert
plugin /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so login
#push “redirect-gateway def1”
#push “dhcp-option DNS 8.8.8.8”
#push “dhcp-option DNS 8.8.4.4”
keepalive 10 120
comp-lzo
user nobody
group nogroup
persist-key
persist-tun
#status /var/log/openvpn/openvpn-status.log
log /var/log/openvpn/openvpn.log
log-append /var/log/openvpn/openvpn.log
verb 3
" > /etc/openvpn/server/server.conf


systemctl start openvpn-server@server

echo "Openvpn is started"
echo " To check status please run systemctl status openvpn-server@server "
}



config () {
sed -i "s/1194/$portvar/g" /etc/openvpn/server/server.conf
}

firewall () {
echo
echo "Firewall configuration"
sudo firewall-cmd --permanent --add-service openvpn &&
sudo firewall-cmd --add-masquerade --permanent &&
sudo firewall-cmd --reload
}


createOPVN () {
echo " OVPN is created in /etc/openvpn/"
IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
ca=$(cat /etc/openvpn/server/ca.crt)

echo "
client
nobind
dev tun
redirect-gateway def1
remote $IP $portvar udp
comp-lzo yes
auth-user-pass pass.txt
auth-nocache
<ca>
$ca
</ca>

" > /etc/openvpn/client.ovpn
}

createUser
update
install
easyrsa
config
firewall
createOPVN


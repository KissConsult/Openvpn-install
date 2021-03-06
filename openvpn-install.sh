##!/bin/bash

#reads the Username and the Port by the user

user=${user:-user}
port=${port:-1194}
password=$(openssl rand -base64 32)

#reads first variable passed, displays help if "-h"
if [ "$1" == "-h" ];then
echo " This script will install and configure an Openvpn server"
echo
echo " Pass the username with --user <user> and the port with --port <port> "
echo " If none is given , defaults will be used"
echo
echo " After the install is complete , you will get a client.ovpn and a pass.txt file in the /etc/openvpn/ directory. Please copy these files to your client ."
echo " Openvpn logs are available in the /var/log/openvpn/ directory"
echo " HTTP logs are available in /var/log/httpry/httpry.log"
echo

 exit 0
fi


#reads the passed variables ,if none the defaults will be used
while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
          if [[ "$param" =~ ^(user|port|password)$ ]]; then
             echo ""
          else
             echo "$param is unknown, using default"
         fi
   fi

  shift
done

echo "User:" $user "Port:" $port "Password:" $password

#test


# creates a random password for the user
caPass=$(openssl rand -base64 32)


# interface SHARK

#SHARK=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}')
SHARK=$(ip link | awk -F: '$0 !~ "lo|vir|wl|tun|^[^0-9]"{print $2;getline}')




#Creates the user and saves in the pass.txt file , this will be used to authenticate the user
createUser () {

sudo useradd $user
sudo echo -e "$password\n$password" | (passwd --stdin $user)
#echo $user\n > /etc/openvpn/pass.txt
#echo $password >> /etc/openvpn/pass.txt
}

# updates the system
update () {
echo
echo "CentOS Update"
sudo yum -y update
echo
}


#installs epel-release, openvpn,easy-rsa
install () {
echo "Installing dependencies"
sudo yum -y install epel-release
sudo yum -y install openvpn
sudo yum -y install wget
sudo yum -y install tar
sudo yum -y install httpry
sudo yum -y install firewalld
systemctl restart firewalld
wget -P /etc/openvpn/ https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
tar -xf /etc/openvpn/EasyRSA-unix-v3.0.6.tgz -C /etc/openvpn/
mv /etc/openvpn/EasyRSA-v3.0.6/ /etc/openvpn/easy-rsa/; rm -f /etc/openvpn/EasyRSA-unix-v3.0.6.tgz
mkdir -p /var/log/openvpn
touch /var/log/openvpn/openvpn.log
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sysctl.conf
echo
}

# First creates the var file with default properties. These can be changed accordingly to need
#
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

# creates the infrascture for the certificates
echo " init pki"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  init-pki /etc/openvpn/easy-rsa/

echo " build-ca"

#/bin/bash /etc/openvpn/easy-rsa/easyrsa  build-ca nopass
echo -e "\n\n" | /bin/bash /etc/openvpn/easy-rsa/easyrsa build-ca nopass

echo " gen-req"

#/bin/bash /etc/openvpn/easy-rsa/easyrsa gen-req hakase-server nopass
printf '\ny\n' | /bin/bash /etc/openvpn/easy-rsa/easyrsa gen-req hakase-server nopass

echo " sign-req"
printf 'yes\n' | /bin/bash /etc/openvpn/easy-rsa/easyrsa  sign-req server hakase-server

echo " client gen-req"
printf '\ny\n' | /bin/bash /etc/openvpn/easy-rsa/easyrsa   gen-req $user nopass

echo " client sign-req"
printf 'yes\n' | /bin/bash /etc/openvpn/easy-rsa/easyrsa sign-req client $user

echo " gen-dh"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  gen-dh
echo " gen-crl"
/bin/bash /etc/openvpn/easy-rsa/easyrsa  gen-crl



#copy the certificates
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/issued/hakase-server.crt /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/private/hakase-server.key /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/server/
cp /etc/openvpn/easy-rsa/pki/issued/$user.crt /etc/openvpn/client/
cp /etc/openvpn/easy-rsa/pki/private/$user.key /etc/openvpn/client/


# creates the server config file
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
#verify-client-cert none
#plugin /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so login
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"


cipher AES-256-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
auth SHA512
auth-nocache


keepalive 10 120
user nobody
group nobody
persist-key
persist-tun
#status /var/log/openvpn/openvpn-status.log
log /var/log/openvpn/openvpn.log
log-append /var/log/openvpn/openvpn.log
verb 3
" > /etc/openvpn/server/server.conf

setenforce 0
sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config

# starts the server
sudo systemctl start openvpn-server@server
echo "*********************************"
echo "Openvpn is started"
echo " To check status please run systemctl status openvpn-server@server "
echo "*********************************"

}


#Changes the default port with the given one
config () {
sudo sed -i "s/1194/$port/g" /etc/openvpn/server/server.conf
echo $user > /etc/openvpn/pass.txt
echo $password >> /etc/openvpn/pass.txt
}

#Adds openvpn service to the firewall and the UDP port ,given by the user
firewall () {
echo "**********************"
echo "Firewall configuration"
echo "**********************"

sudo firewall-cmd --permanent --add-service openvpn
sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --permanent --add-port=$port/udp
sudo firewall-cmd --permanent --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.5.0.0/24 -o $SHARK -j MASQUERADE
sudo firewall-cmd --reload
}

#Creates the ovpn file based on the username. Copys the ca.crt file and the IP of the server
createOPVN () {
echo "*********************************"
echo " OVPN is created in /etc/openvpn/"
echo "*********************************"

IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
ca=$(cat /etc/openvpn/server/ca.crt)
cert=$(cat /etc/openvpn/client/$user.crt)
key=$(cat /etc/openvpn/client/$user.key)

echo "
client
nobind
dev tun
redirect-gateway def1
remote $IP $port udp
#auth-user-pass pass.txt
cipher AES-256-CBC
auth SHA512
auth-nocache
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256

<ca>
$ca
</ca>
<cert>
$cert
</cert>
<key>
$key
</key>


" > /etc/openvpn/client.ovpn
}

httpry () {
echo "*******************************"
echo "Create and start httpry-service"
echo "*******************************"


echo "
[Unit]
After=network.target

[Service]
Restart=always
RestartSec=30
ExecStartPre=/bin/mkdir -p /var/log/httpry/
ExecStart=/usr/sbin/httpry -i $SHARK -d -F -o /var/log/httpry/httpry.log
ExecStop=/bin/kill -s QUIT $MAINPID

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/httpry.service

systemctl daemon-reload
systemctl enable httpry.service
systemctl start httpry.service
}

restartopenvpn () {
# restarts the server with new config

sudo systemctl enable openvpn-server@server
sudo systemctl restart openvpn-server@server
echo "*******************************"
echo "Openvpn is started"
echo " To check status please run systemctl status openvpn-server@server "
echo "*******************************"

}

update
createUser
install
easyrsa
config
firewall
createOPVN
restartopenvpn
httpry

# the passwd disp is only once!
rm /etc/openvpn/pass.txt

echo "User:" $user "Port:" $port "Password:" $password

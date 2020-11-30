#! /bin/bash

#reads the Username and the Port by the user 
read () {
read -p 'Username: ' uservar
read -p 'Port: ' portvar
}
# creates a random password for the user
password=$(openssl rand -base64 32)
caPass=$(openssl rand -base64 32)

#Creates the user and saves in the pass.txt file , this will be used to authenticate the user
createUser () {

sudo useradd $uservar
sudo echo -e "$password\n$password" | (passwd --stdin $uservar)
echo $uservar\n > /etc/openvpn/pass.txt
echo $password >> /etc/openvpn/pass.txt
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
sudo yum -y install epel-release &&
sudo yum -y install openvpn &&
sudo yum -y install easy-rsa
wget -P /etc/openvpn/ https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
tar -xf /etc/openvpn/EasyRSA-unix-v3.0.6.tgz
mv /etc/openvpn/EasyRSA-v3.0.6/ /etc/openvpn/easy-rsa/; rm -f /etc/openvpn/EasyRSA-unix-v3.0.6.tgz
touch /var/log/openvpn/openvpn.log
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


#copy the certificates
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/issued/hakase-server.crt /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/private/hakase-server.key /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/server/ &&
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/server/


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
verify-client-cert nocert
plugin /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so login
#push “redirect-gateway def1”
#push “dhcp-option DNS 8.8.8.8”
#push “dhcp-option DNS 8.8.4.4”
keepalive 10 120
user nobody
group nogroup
persist-key
persist-tun
#status /var/log/openvpn/openvpn-status.log
log /var/log/openvpn/openvpn.log
log-append /var/log/openvpn/openvpn.log
verb 3
" > /etc/openvpn/server/server.conf

# starts the server
sudo systemctl start openvpn-server@server

echo "Openvpn is started"
echo " To check status please run systemctl status openvpn-server@server "
}


#Changes the default port with the given one 
config () {
sudo sed -i "s/1194/$portvar/g" /etc/openvpn/server/server.conf
}

#Adds openvpn service to the firewall and the UDP port ,given by the user 
firewall () {
echo
echo "Firewall configuration"
sudo firewall-cmd --permanent --add-service openvpn
sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --permanent --add-port=$portvar/udp
sudo firewall-cmd --reload
}

#Creates the ovpn file based on the username. Copys the ca.crt file and the IP of the server
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
auth-user-pass pass.txt
auth-nocache
<ca>
$ca
</ca>

" > /etc/openvpn/client.ovpn
}

#starts httpry in a deamon and logs all the http request in the httpry.log file
httpry () {
 sudo yum -y install httpry
 httpry -do /etc/openvpn/httpry.log
}

# Displays the help segment, can be called with the "-h" syntax 
Help() {

echo " This script will install and configure an Openvpn server"
echo
echo " At the prompt please enter a username and a port on which the server will listen "
echo
echo " After the install is complete , you will get a client.ovpn and a pass.txt file in the /etc/openvpn/ directory. Please copy these files to your client ."
echo
echo " The http log is found in the /etc/openvpn/httpry.log "
echo

}
# For showing the help function
while getopts ":h" option; do
   case $option in
      h) # display Help
         Help
         exit;;
   esac
done

read
createUser
update
install
easyrsa
config
firewall
createOPVN
httpry

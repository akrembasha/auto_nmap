#!/bin/bash
#
# winshock.sh
#
# Authors:
# Stephan Peijnik <speijnik@anexia-it.com>
#
# The MIT License (MIT)
#
# Copyright (c) 2014 ANEXIA Internetdienstleistungs GmbH
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
VERSION=0.2.1
HOST=$1
PORT=${2:-443}
if [ -z "$HOST" -o -z "$PORT" ]
then
echo "Usage: $0 host [port]"
echo "port defaults to 443."
exit 1
fi

echo ""
# According to https://technet.microsoft.com/library/security/ms14-066 the
# following ciphers were added with the patch:
# * TLS_DHE_RSA_WITH_AES_256_GCM_SHA384
# * TLS_DHE_RSA_WITH_AES_128_GCM_SHA256
# * TLS_RSA_WITH_AES_256_GCM_SHA384
# * TLS_RSA_WITH_AES_128_GCM_SHA256
#
# The OpenSSL cipher names for these ciphers are:
MS14_066_CIPHERS="DHE-RSA-AES256-GCM-SHA384 DHE-RSA-AES128-GCM-SHA256 AES256-GCM-SHA384 AES128-GCM-SHA256"
# Ciphers supported by Windows Server 2012R2
WINDOWS_SERVER_2012R2_CIPHERS="ECDHE-RSA-AES256-SHA384 ECDHE-RSA-AES256-SHA"
# Test if OpenSSL does support the ciphers we're checking for...
echo -n "Testing if OpenSSL supports the ciphers we are checking for: "
openssl_ciphers=$(openssl ciphers)
for c in $MS14_066_CIPHERS
do
if ! echo $openssl_ciphers | grep -q $c 2>&1 >/dev/null
then
echo -e "\033[91mNO\033[0m (OpenSSL does not support $c cipher.)"
echo -e "Aborting."
exit 5
fi
done
echo -e "YES"
SERVER=$HOST:$PORT
echo -e "\nTesting ${SERVER} for availability of SSL ciphers added in MS14-066..."
patched="no"
for cipher in ${MS14_066_CIPHERS}
do
echo -en "Testing cipher ${cipher}: "
result=$(echo -n | openssl s_client -cipher "$cipher" -connect $SERVER 2>&1)
if [[ "$result" =~ "connect:errno=" ]]
then
err=$(echo $result | grep ^connect: \
| sed -e 's/connect:errno=.*//g' -e 's/connect: //g')
echo -e "Connection error: $err"
echo -e "Aborting checks."
exit 1
elif [[ "$result" =~ "SSL23_GET_SERVER_HELLO:unknown protocol" ]]
then
echo -e "\033[91mNO\033[0m SSL/TLS support on target port."
echo -e "Aborting checks."
exit 1
elif [[ "$result" =~ "SSL_CTX_set_cipher_list:no cipher match" ]]
then
echo -e "Your version of OpenSSL is not supported."
echo -e "Aborting checks.\033[39m"
exit 1
elif [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher : ${cipher}" ]]
then
echo -e "SUPPORTED"
if [[ "$patched" == "no" ]]
then
patched="yes"
fi
else
echo -e "UNSUPPORTED"
fi
done
windows_server_2012_or_later="no"
windows_server_2012_r2="no"
iis_detected="no"
# added by @stoep: check whether a 443 port runs IIS
if [[ "$PORT" == "443" ]]
then
iis=$(curl -k -I https://$SERVER 2> /dev/null | grep "Server" )
echo -n "Testing if IIS is running on port 443: "
if [[ $iis == *Microsoft-IIS* ]]
then
iis_version=$(echo $iis | sed -e 's|Server: Microsoft-IIS/||g')
iis_detected="yes"
echo -e "YES - Version ${iis_version}"
if [[ $iis_version == *8.5* ]]
then
echo -e "Windows Server 2012 R2 detected. Results of this script will be inconclusive."
windows_server_2012_or_later="yes"
windows_server_2012_r2="yes"
elif [[ $iis_version == *8.0* ]]
then
windows_server_2012_or_later="yes"
windows_server_2012_r2="no"
fi
else
echo -e "NO"
fi
fi
# Check if Windows Server 2012 or later is running on the remote system...
if [[ "$windows_server_2012_or_later" == "no" && "$iis_detected" == "no" ]]
then
echo -e "\033[94mChecking if target system is running Windows Server 2012 or later..."
for cipher in ${WINDOWS_SERVER_2012R2_CIPHERS}
do
echo -en "Testing cipher ${cipher}: "
result=$(echo -n | openssl s_client -cipher "$cipher" -connect $SERVER 2>&1)
if [[ "$result" =~ "connect:errno=" ]]
then
err=$(echo $result | grep ^connect: \
| sed -e 's/connect:errno=.*//g' -e 's/connect: //g')
echo -e "Connection error: $err"
echo -e "Aborting checks."
exit 1
elif [[ "$result" =~ "SSL23_GET_SERVER_HELLO:unknown protocol" ]]
then
echo -e "No SSL/TLS support on target port."
echo -e "Aborting checks."
exit 1
elif [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher : ${cipher}" ]]
then
echo -e "SUPPORTED"
if [[ "$windows_server_2012_or_later" == "no" ]]
then
windows_server_2012_or_later="yes"
break
fi
else
echo -e "UNSUPPORTED"
fi
done
fi
if [[ "$patched" == "yes" && "$windows_server_2012_or_later" == "no" ]]
then
patched="YES"
elif [[ "$patched" == "yes" ]]
then
patched="UNKNOWN"
if [[ "$windows_server_2012_r2" == "yes" ]]
then
patched="$patched: Windows Server 2012 R2 detected."
else
patched="$patched: Windows Server 2012 or later detected."
fi
else
patched="\033[91mNO\033[0m"
fi
echo -e "\033[94m$SERVER is patched: $patched"
echo -e "\n"
cat <<EOF
EOF
echo -en ""
exit 0

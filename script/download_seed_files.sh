#!/bin/bash

curl -Lo uploads00.tar.gz https://github.com/ambry-app/ambry/releases/download/v1.4.0/uploads00.tar.gz
curl -Lo uploads01.tar.gz https://github.com/ambry-app/ambry/releases/download/v1.4.0/uploads01.tar.gz
curl -Lo uploads02.tar.gz https://github.com/ambry-app/ambry/releases/download/v1.4.0/uploads02.tar.gz

cat uploads*.tar.gz | tar xzpvf -
tar -xvf uploads.tar.gz

rm uploads.tar.gz
rm uploads00.tar.gz
rm uploads01.tar.gz
rm uploads02.tar.gz

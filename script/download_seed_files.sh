#!/bin/bash

SEED_FILES=https://github.com/ambry-app/ambry/releases/download/v1.4.0/uploads.tar.gz

curl -Lo uploads.tar.gz $SEED_FILES

tar -xvzf uploads.tar.gz

rm uploads.tar.gz

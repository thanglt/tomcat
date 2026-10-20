ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-localcdn/target/webapp-current cdn

ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-admin/target/webapp-current admin

ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-retailers/target/webapp-current retailers

ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-customer/target/webapp-current customer

ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-server/target/webapp-current server
ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-takeout/target/webapp-current takeout


ln -s /home/sunnypoint/src/sunnypoint-v3/napolinokama-web/target/webapp-current napolinokama
ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-mobile-stores/target/webapp-current stores
ln -s /home/sunnypoint/src/sunnypoint-v3/shopping-escents/target/webapp-current escents


ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-liquibase-runner/target/webapp-current liquibase
ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-batch/target/webapp-current /home/sunnypoint/tomcats/batch/webapps/batch

ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-coupon-batch/target/webapp-current coupon-batch

ln -s /home/sunnypoint/src/sunnypoint-v3/sunnypoint-message-sender/target/webapp-current sender


mkdir /home/sunnypoint/tomcats/webapps/webapps/admin
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/admin
mkdir /home/sunnypoint/tomcats/webapps/webapps/retailers
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/retailers

mkdir /home/sunnypoint/tomcats/webapps/webapps/customer
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/customer

mkdir /home/sunnypoint/tomcats/webapps/webapps/takeout
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/takeout

mkdir /home/sunnypoint/tomcats/webapps/webapps/napolinokama
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/napolinokama

mkdir /home/sunnypoint/tomcats/webapps/webapps/stores
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/stores


mkdir /home/sunnypoint/tomcats/webapps/webapps/server
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/server

mkdir /home/sunnypoint/tomcats/webapps/webapps/escents
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/escents

mkdir /home/sunnypoint/tomcats/webapps/webapps/v2server
chmod 777 /home/sunnypoint/tomcats/webapps/webapps/v2server

cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-admin/target/webapp-current/. admin

cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-server/target/webapp-current/. server
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-version2-core/target/webapp-current/. v2server

rm -rf /home/sunnypoint/tomcats/webapps/webapps/admin/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/retailers/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/customer/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/server/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/takeout/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/napolinokama/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/stores/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/escents/*
rm -rf /home/sunnypoint/tomcats/webapps/webapps/V2server/*


cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-admin/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/admin
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-retailers/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/retailers
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-customer/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/customer
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-server/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/server
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-takeout/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/takeout
cp -a /home/sunnypoint/src/sunnypoint-v3/napolinokama-web/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/napolinokama
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-web-mobile-stores/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/stores
cp -a /home/sunnypoint/src/sunnypoint-v3/shopping-escents/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/escents
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-version2-server/target/webapp-current/. /home/sunnypoint/tomcats/webapps/webapps/v2server



rm -rf /home/sunnypoint/tomcats/batch/webapps/liquibase-runner/*
rm -rf /home/sunnypoint/tomcats/batch/webapps/batch/*
rm -rf /home/sunnypoint/tomcats/batch/webapps/coupon-batch/*
rm -rf /home/sunnypoint/tomcats/batch/webapps/message-sender/*

cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-liquibase-runner/target/webapp-current/. /home/sunnypoint/tomcats/batch/webapps/liquibase-runner
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-batch/target/webapp-current/. /home/sunnypoint/tomcats/batch/webapps/batch
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-coupon-batch/target/webapp-current/. /home/sunnypoint/tomcats/batch/webapps/coupon-batch
cp -a /home/sunnypoint/src/sunnypoint-v3/sunnypoint-message-sender/target/webapp-current/. /home/sunnypoint/tomcats/batch/webapps/message-sender




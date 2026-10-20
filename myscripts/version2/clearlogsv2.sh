#!/bin/bash
# Clear the logs of the Tomcat of sunnypoint-version2-server and the files in ~/logs/sunnypoint whose name contains "v2"
TOMCAT_V2=/Users/thanglt/tomcat/apache-tomcat-10.1.57-v2
rm -rf "$TOMCAT_V2"/logs/*
find ~/logs/sunnypoint -type f -name '*v2*' -delete 2>/dev/null

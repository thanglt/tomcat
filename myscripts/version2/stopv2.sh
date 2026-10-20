#!/bin/bash
# Stop the Tomcat of sunnypoint-version2-server by killing its process
TOMCAT_V2=/Users/thanglt/tomcat/apache-tomcat-10.1.57-v2
PIDS=$(pgrep -f "catalina.base=$TOMCAT_V2")
if [ -z "$PIDS" ]; then
  echo "Tomcat v2 is not running"
  exit 0
fi
kill $PIDS
for i in {1..15}; do
  pgrep -f "catalina.base=$TOMCAT_V2" > /dev/null || { echo "Tomcat v2 stopped"; exit 0; }
  sleep 1
done
echo "Tomcat v2 still running, kill -9"
kill -9 $(pgrep -f "catalina.base=$TOMCAT_V2")

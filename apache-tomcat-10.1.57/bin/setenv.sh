# TC-MULTI-INSTANCE v2 — setenv.sh dùng chung cho mọi instance
# Thứ tự: mặc định -> instance.env -> option chung -> override/setenv.sh -> port + EXTRA_OPTS

# 1) Mặc định (dùng khi chạy chính Tomcat gốc) + giá trị riêng của instance
HTTP_PORT=83
SHUTDOWN_PORT=8005
EXTRA_OPTS=""
[ -r "$CATALINA_BASE/instance.env" ] && . "$CATALINA_BASE/instance.env"

CATALINA_PID="$CATALINA_BASE/temp/tomcat.pid"
CATALINA_OUT="$CATALINA_BASE/logs/catalina.out"

# 2) Option chung (sửa ở đây để áp dụng cho mọi instance)
# JAVA_HOME=/path/to/jdk
# ---- giữ lại từ setenv.sh cũ (setenv.sh.bak.20261019084840) ----
 
# Overrides configuration (DB password, etc)
export CLASSPATH="/Users/thanglt/etc/"
export JAVA_OPTS="$JAVA_OPTS -Xmx2048m -Dfile.encoding=UTF-8 -Dspring.cache.engine=redis"

export JPDA_ADDRESS=0.0.0.0:${DEBUG_PORT:-$((HTTP_PORT + 9000))}   # mỗi instance một cổng debug (HTTP_PORT+9000; đổi bằng DEBUG_PORT trong instance.env)
export JPDA_TRANSPORT=dt_socket
export JPDA_HOST=localhost
export JAVA_OPTS="$JAVA_OPTS -Dsun.rmi.dgc.server.gcInterval=3600000"
export JAVA_OPTS="-Xdebug -Xnoagent -Xrunjdwp:transport=$JPDA_TRANSPORT,address=$JPDA_ADDRESS,server=y,suspend=n $JAVA_OPTS"
# ---- hết phần cũ ----

# 3) Override riêng của instance (ưu tiên hơn phần chung)
if [ "$CATALINA_BASE" != "$CATALINA_HOME" ] && [ -r "$CATALINA_BASE/override/setenv.sh" ]; then
  . "$CATALINA_BASE/override/setenv.sh"
fi

# 4) Luôn thêm cuối: port cho server.xml chung + EXTRA_OPTS
CATALINA_OPTS="$CATALINA_OPTS -Dport.http=$HTTP_PORT -Dport.shutdown=$SHUTDOWN_PORT $EXTRA_OPTS"

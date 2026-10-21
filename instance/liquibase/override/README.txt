Đặt file cần override vào đây:
- setenv.sh    : được source SAU setenv chung -> giá trị ở đây thắng.
                 Nối thêm: CATALINA_OPTS="$CATALINA_OPTS -Xmx2g"   | Thay hẳn: CATALINA_OPTS="-Xmx4g"
- *.properties : chỉ ghi các key cần đổi -> merge, key ở đây thắng.
- File khác (web.xml, context.xml, tomcat-users.xml, server.xml...) : thay toàn bộ file chung.
Sau khi sửa: tc.sh restart <name>

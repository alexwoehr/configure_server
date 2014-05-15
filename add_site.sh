#!/bin/sh

echo "Not implemented yet."
exit 255

# Adding a user
echo "1. Create client dir / site dir"
echo "2. Create ftp group / head ftp user for client"
echo "3. Set group to FTP group and user to apache"
echo "4. Add apache to supplemental group for FTP group"
echo "5. Create logs"
echo "6. Setup httpd config"
echo "7. Add logs to logrotate"
echo "Remind user to document site"
echo "Setup git ignore and backup ignore files for this site."
# make sure that /srv/client is httpd_sys_content_t, or httpd_sys_content_rw_t, but /srv/client/logs is httpd_log_t
# or could use public_content_t to make FTP more secure???


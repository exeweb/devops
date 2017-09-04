#!/bin/bash
curdir=$(pwd)
#Test system
totalmem=$(free -m|grep Mem|awk '{ print $2 }')
if (($totalmem>2000))
    then
# Install Docker
echo Install Docker ...
apt-get update
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
apt-add-repository 'deb https://apt.dockerproject.org/repo ubuntu-xenial main'
apt-get update
apt-get install -y docker-engine

# Create folders for config and data files
echo Create folders ...
mkdir project
chmod 755 project
mkdir project/mysql
chmod 755 project/mysql
mkdir project/nginx
chmod 755 project/nginx
mkdir project/backup
chmod 755 project/backup

# Install Mysql Jira Nginx containers
echo Install Mysql Jira Nginx containers ...

# Create Mysql container
# Ask about Mysql parameters
echo Create Mysql container ...
echo -en "\033[37;1;43m > \033[0m"
echo Please type name for database:
read dbname
echo -en "\033[37;1;43m > \033[0m"
echo Create Mysql user for database $dbname
echo -en "\033[37;1;43m > \033[0m"
echo Please type username:
read dbuser
echo -en "\033[37;1;43m > \033[0m"
echo Please type password:
read dbpassword
rootpassword='myrootpass'
docker run --name mysql -v $curdir/project/mysql:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=$rootpassword -e MYSQL_DATABASE=$dbname -e MYSQL_USER=$dbuser -e MYSQL_PASSWORD=$dbpassword -d mysql:5.7 

# Find Mysql container ip adress
sleep 2
mysqlid=$(docker ps|grep mysql| awk '{ print $1 }')
mysqlip=$(docker inspect --format '{{ .NetworkSettings.Networks.bridge.IPAddress }}' $mysqlid)

# Create Jira container
echo Create Jira container ...
docker run --name jira --detach cptactionhank/atlassian-jira:latest

# Find Jira container ip adress
sleep 2
jiraid=$(docker ps|grep jira| awk '{ print $1 }')
jiraip=$(docker inspect --format '{{ .NetworkSettings.Networks.bridge.IPAddress }}' $jiraid)

# Create Nginx container
echo Create Nginx container ...
# Ask about external port for reverse proxy
echo -en "\033[37;1;43m > \033[0m"
echo Enter the port number on which the ginx will respond
read nginxport
# Create nginx.conf
tee "$curdir/project/nginx/nginx.conf" > /dev/null <<EOF
events{
}
http{
server {
  listen $nginxport;
    location / {
       proxy_pass http://$jiraip:8080/;
         }
     }
}
EOF
chmod 644 $curdir/project/nginx/nginx.conf
#cp nginx.conf $curdirr/project/nginx/
#rm nginx.conf
docker run --name nginx -p $nginxport:$nginxport -v $curdir/project/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -d nginx

# Find Nginx container ip adress
sleep 2
nginxid=$(docker ps|grep nginx| awk '{ print $1 }')
echo $nginxid
nginxip=$(docker inspect --format '{{ .NetworkSettings.Networks.bridge.IPAddress }}' $nginxid)
echo $nginxip

# Add firewall rule
echo Create firewall rule ...
iptables -I INPUT -p tcp --dport $nginxport -j ACCEPT 
# Add firewall rule to autostart file (rc.local)
echo iptables -I INPUT -p tcp --dport $nginxport -j ACCEPT >> /etc/rc.local

# Create control script
echo Create control script ...
tee "control.sh" > /dev/null <<EOF
#!/bin/bash
#
echo What do you want do with container-s?
echo [1]-Start  [2]-Stop  [3]-Restart
read choice
if ((\$choice==1))
    then
    echo What container-s you want to start?
    echo [1]-Nginx [2]-Jira [3]-Mysql [4]-All this
    read startvar
	if ((\$startvar==1))
	    then
	    docker start nginx
	elif ((\$startvar==2))
	    then
	    docker start jira
	elif ((\$startvar==3))
	    then
	    docker start mysql
	elif ((\$startvar==4))
	    then
	    docker start mysql
	    docker start jira
	    docker start nginx
	else
	    echo Wrong type
	fi
elif ((\$choice==2))
    then
    echo What container-s you want to stop?
    echo [1]-Nginx [2]-Jira [3]-Mysql [4]-All this
    read stopvar
	if ((\$stopvar==1))
	    then
	    docker stop nginx
	elif ((\$stopvar==2))
	    then
	    docker stop jira
	elif ((\$stopvar==3))
	    then
	    docker stop mysql
	elif ((\$stopvar==4))
	    then
	    docker stop nginx
	    docker stop jira
	    docker stop mysql
	else
	    echo Wrong type
	fi
elif ((\$choice==3))
    then
    echo What container-s you want to restart?
    echo [1]-Nginx [2]-Jira [3]-Mysql [4]-All this
    read restartvar
	if ((\$restartvar==1))
	    then
	    docker restart nginx
	elif ((\$restartvar==2))
	    then
	    docker restart jira
	elif ((\$restartvar==3))
	    then
	    docker restart mysql
	elif ((\$restartvar==4))
	    then
	    docker restart mysql
	    docker restart jira
	    docker restart nginx
	else
	    echo Wrong type
	fi
else
    echo Wrong type
fi
EOF
chmod 777 control.sh

# Create backup script
apt-get install -y zip
tee "manualbackup.sh" > /dev/null <<EOF
#!/bin/bash
#
cd $curdir
date="/bin/date"
ts=\`\$date +%H_%M-%d.%m.%y\`
path=\$(pwd)
mkdir tmp
docker exec mysql /usr/bin/mysqldump -u $dbuser --password=$dbpassword $dbname > \$path/tmp/backup.sql
cp note.txt \$path/tmp/
cp \$path/project/nginx/nginx.conf \$path/tmp/
zip -r -j \$path/project/backup/backup-\$ts.zip \$path/tmp/
rm -r tmp
EOF
chmod 777 manualbackup.sh
cp manualbackup.sh /etc/cron.hourly/backup

# Create postinstall note
echo Create postinstall note ...
tee "note.txt" > /dev/null <<EOF
For access to jira use this URL http://<IP_OF_THIS_PC:$nginxport>/

Jira container local ip - $jiraip

Info for database connection
Database host(container local ip) - $mysqlip
Database root password - $rootpassword
Database name - $dbname
Database user - $dbuser
Database password - $dbpassword
Mysql data folder - $curdir/project/mysql

Nginx config folder - $curdir/project/nginx
Nginx container local ip - $nginxip

Folder for backup (database dump and nginx.config) - $curdir/project/backup
Backup files named with create time

Script for auto-backup added to /etc/cron.hourly/

Script for backup - manualbackup.sh
use it with sudo

Script for control container(stop start restart) - control.sh
use it with sudo

EOF

echo -en "\033[37;1;41m Read! >>  \033[0m"
echo For continue installation of Jira use web-browser and url http://IP_OF_THIS_PC:$nginxport/
echo Parameters for connection to Mysql and others tech info you can find in note.txt
sleep 5

else
echo Do not have memory!
echo Need more 2Gb!
fi
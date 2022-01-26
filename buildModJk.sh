#!/bin/bash

#---------------
# Variables
base=/opt
aprVer="1.7.0"
aprUtilVer="1.6.1"
httpdVer="2.4.52"
modJKVer="1.2.48"
tmpFolder="/root/httpd"
srcFolder="/root/src"
logFile="/root/compile.log"
jdk="https://download.java.net/java/GA/jdk16.0.1/7147401fd7354114ac51ef3e1328291f/9/GPL/openjdk-16.0.1_linux-x64_bin.tar.gz"
tomcatVer="10.0.16"
apacheBase="https://dlcdn.apache.org"
testBinary=0

tomcatInstance=3
tomcatPort=8100
tomcatShut=8200
tomcatAJP=8300
requests=10000
concurrent=500

#--------------
# Scripts

cmdOk=/bin/true

function write ()
{
 echo -n "${1}"  | tee -a $logFile
} 

function writeln ()
{
 echo "${1}" | tee -a $logFile
}

function result ()
{
  failed=0
  case ${1} in
  0) 
   write "Success" 
   ;;
  1) 
   write "Failed"  ; failed=1
   ;;
  99) 
   write "Skipped" 
   ;;
  *) 
   write "Failed" ; failed=1
   ;;
  esac
  [[ ${1} -eq 0 ]] || [[ -z "${2}" ]] && writeln "" || writeln "(Msg: ${2})"
  [[ $failed -ne 0 ]] && exit 1
}

function run ()
{
 taskName=${1}
 shift
 msg=${1}
 shift
 compileLog=${1}
 shift 
 [[ ! -z "${taskName}" ]] && write "${taskName}... "
 while (($#)) ; do 
  if [[ ! -z "${compileLog}" ]] ; then 
   echo "${taskName}" >> "${tmpFolder}/${compileLog}"
   echo "--------------------------------------------------" >> "${tmpFolder}/${compileLog}"
   eval ${1} >> "${tmpFolder}/${compileLog}" 2>&1
   result=$?   
   echo "" >> "${tmpFolder}/${compileLog}"
  else
   eval ${1} >/dev/null 2>&1
   result=$?
  fi
  [[ $result -ne 0 ]] && break
  shift
 done
 [[ ! -z "${taskName}" ]] && result $result ${msg}
}

function download () 
{
 file=$(echo ${1} | awk -F/ '{print $NF}')
 [[ ! -f $srcFolder"/"${file} ]] && run " - Downloading ${file}" "" "" "wget ${1} -O ${srcFolder}/${file}"
}

function compileApr ()
{
 writeln "Building APR..." "log"
 run "" "" "" "cd ${tmpFolder}"
 run " - Removing folder apr-${aprVer}" "" "" "rm -fr apr-${aprVer}" 
 download "${apacheBase}/apr/apr-${aprVer}.tar.gz"
 run " - Untaring apr-${aprVer}" "" "" "tar -zxvf ${srcFolder}/apr-${aprVer}.tar.gz"
 run "" "" "" "cd apr-$aprVer"
 run " - Configuring apr-${aprVer}" "" "apr.log" "./configure --prefix=${base}/apr"
 run " - Making apr-${aprVer}" "" "apr.log" "make"
 [[ $testBinary -eq 1 ]] && run " - Testing compuled apr-${aprVer}" "" "apr.log" "make test"
 run " - Installing apr-${aprVer}" "" "" "make install"
 run "" "" "" "cd .."
 writeln ""
}

function compileAprUtil ()
{
 writeln "Building APR-Util ..." "log"
 run "" "" "" "cd ${tmpFolder}"
 run " - Removing folder apr-util-${aprUtilVer}" "" "" "rm -fr apr-util-${aprUtilVer}"
 download "${apacheBase}/apr/apr-util-$aprUtilVer.tar.gz"
 run " - Untaring apr-util-${aprUtilVer}.tar.gz" "" "" "tar -zxvf ${srcFolder}/apr-util-${aprUtilVer}.tar.gz"
 run "" "" "" "cd apr-util-${aprUtilVer}"
 run " - Installing expat and expat-devel" "" "" "yum install expat expat-devel -y"
 run " - Configuring apr-util-${aprUtilVer}" "" "aprUtil.log" "./configure --with-apr=/root/httpd/apr-$aprVer --prefix=$base/apr"
 run " - Making apr-util-${aprUtilVer}" "" "aprUtil.log" "make"
 run " - Installing apr-util-${aprUtilVer}" "" "aprUtil.log" "make install"
 run "" "" "" "cd .."
 writeln ""
}

function compileHttpd ()
{
 writeln "Building httpd ..."
 run "" "" "" "cd ${tmpFolder}"
 run " - Removing folder httpd-${httpdVer}" "" "" "rm -fr httpd-${httpdVer}"
 download "${apacheBase}/httpd/httpd-${httpdVer}.tar.gz"
 run " - Untaring httpd-${httpdVer}" "" "" "tar -zxvf ${srcFolder}/httpd-${httpdVer}.tar.gz"
 run "" "" "" "cd httpd-${httpdVer}"
 run " - Install pcre, pcre-devel and perl" "" "" "yum install pcre pcre-devel perl -y"
 run " - Compling  httpd-${httpdVer}" "" "httpd.log" "./configure --prefix=${base}/httpd --with-apr=/root/httpd/apr-${aprVer} --with-apr-util=/root/httpd/apr-util-${aprUtilVer}"
 run " - Making httpd-${httpdVer}" "" "httpd.log" "make"
 run " - Installing httpd-${httpdVer}" "" "httpd.log" "make install"
 run " - Copying httpd.init to /etc/init.d" "" "" "cp ${tmpFolder}/httpd-${httpdVer}/build/rpm/httpd.init  /etc/init.d/httpd"
 run " - Adding httpd to service" "" "" "chkconfig --add httpd"
 httpdConf=$(cat <<EOF
HTTPD=/BASEFOLDER/httpd/bin/httpd
#PIDFILE=/BASEFOLDER/httpd/logs/httpd.pid
PIDFILE=/var/run/httpd.pid
EOF
 )
 run " - Adding /etc/sysconfig.httpd" "" "" 'echo "${httpdConf}" > /etc/sysconfig/httpd'
 run " - Configuring /etc/sysconfig/httpd" "" "" "sed -i s#/BASEFOLDER#${base}#g /etc/sysconfig/httpd"
 run "" "" "" "mkdir /etc/httpd/conf -p" 
 run "" "" "" "ln -s $base/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf"
 run " - Adding ServerName to httpd.conf" "" "" "echo ServerName `hostname` >> $base/httpd/conf/httpd.conf"
 run " - Adding PidFile to httpd.conf" "" "" "echo PidFile /var/run/httpd.pid >> $base/httpd/conf/httpd.conf"
 run "" "" "" "cd .."
 writeln ""
}

function compileModJK ()
{
 writeln "Building mod_jk ..."
 run "" "" "" "cd ${tmpFolder}"
 run "" "" "" "rm -fr tomcat-connectors-${modJKVer}-src"
 download "${apacheBase}/tomcat/tomcat-connectors/jk/tomcat-connectors-$modJKVer-src.tar.gz"
 run " - Untaring tomcat-connectors-${modJKVer}-src" "" "" "tar -zxvf ${srcFolder}/tomcat-connectors-$modJKVer-src.tar.gz"
 run "" "" "" "cd tomcat-connectors-${modJKVer}-src/native/"
 run " - Configuring tomcat-connectors-${modJKVer}" "" "modjk.log" "./configure  --with-apxs=${base}/httpd/bin/apxs"
 run " - Making tomcat-connectors-${modJKVer}" "" "modjk.log" "make"
 run " - Installing tomcat-connectors-${modJKVer}" "" "modjk.log" "make install"
 modjkConf=$(cat <<EOF 
LoadModule jk_module modules/mod_jk.so
EOF
 )
 run " - Creating modJK config" "" "" 'echo "${modjkConf}" > ${base}/httpd/conf/extra/jk_modules.conf'
 run " - Modifying ${base}/httpd/conf/httpd.conf" "" "" "echo Include conf/extra/jk_modules.conf >> ${base}/httpd/conf/httpd.conf"
 run " - Restarting httpd" "" "" "service httpd restart"
 run " - Make sure mod_jk is loaed" "" "" "${base}/httpd/bin/apachectl -M | grep jk"
 run "" "" "" "cd ../.."
 writeln ""
}

function installJDK ()
{
 writeln "Installing JDK"
 run "" "" "" "cd ${tmpFolder}"
 run "" "" "" "rm -fr $(find ${tmpFolder} -maxdepth 1 -iname jdk-* -type d)"
 download "${jdk}"
 run " - Untaring $(echo ${jdk} | awk -F/ '{print $NF}')" "" "" "tar -zxvf $(find ${srcFolder} -iname 'openjdk*' -type f)"
 run " - Copying JDK to ${base}" "" "" "cp -r $(find ${tmpFolder} -maxdepth 1 -iname "jdk-*" -type d) ${base}"
 run " - Creating symlink ${base}/java" "" "" "ln -s $(find ${base} -maxdepth 1 -iname 'jdk-*' -type d) ${base}/java"
 writeln ""
}

function installTomcat ()
{
 writeln "Building tomcat ..."
 run " - Creating foler ${base}/tomcat if not exist" "" "" "mkdir -p ${base}/tomcat"
 run "" "" "" "cd ${tmpFolder}"
 [[ -z "$(id tomcat 2>/dev/null)" ]] && run " - Adding user tomcat" "" "" "useradd -d /opt/tomcat tomcat"
 run "" "" "" "rm -fr apache-tomcat-${tomcatVer}"
 url="${apacheBase}/tomcat/tomcat-$(echo ${tomcatVer} | cut -f 1 -d \.)/v${tomcatVer}/bin/apache-tomcat-${tomcatVer}.tar.gz"
 download "$url"
 run " - Untaring $(echo $url | awk -F/ '{print $NF}')" "" "" "tar -zxvf ${srcFolder}/apache-tomcat-${tomcatVer}.tar.gz"
 for i in $(seq 1 ${tomcatInstance}); do
  let pTomcat=${tomcatPort}+${i}
  let pTomcatShut=${tomcatShut}+${i}
  let pTomcatAJP=${tomcatAJP}+${i}
  writeln " - Creating tomcat instance ${i}"
  run "   - Copying tomcat source" "" "" "cp -r ${tmpFolder}/apache-tomcat-${tomcatVer} ${base}/tomcat/apache-tomcat-${tomcatVer}_${i}"
  run "   - Fixing permission" "" "" "chown -R tomcat:tomcat ${base}/tomcat/apache-tomcat-${tomcatVer}_${i}"
  run "   - Creating symlink" "" "" "ln -s ${base}/tomcat/apache-tomcat-${tomcatVer}_${i}/ ${base}/tomcat/tomcat_${i}"
  tomcatInit=$(cat <<\EOF
#!/bin/bash
# chkconfig: 2345 95 20
# description: This application was developed by me and is tested on this server
# processname: my_app
#
# Tomcat 8 start/stop/status init.d script
# Initially forked from: https://gist.github.com/valotas/1000094
# @author: Miglen Evlogiev <bash@miglen.com>
#
# Release updates:
# Updated method for gathering pid of the current proccess
# Added usage of CATALINA_BASE
# Added coloring and additional status
# Added check for existence of the tomcat user
# Added termination proccess
 
#Location of JAVA_HOME (bin files)
export JAVA_HOME=JAVAHOME

#Add Java binary files to PATH
export PATH=$JAVA_HOME/bin:$PATH
 
#CATALINA_HOME is the location of the bin files of Tomcat  
export CATALINA_HOME=CATALINAHOME
 
#CATALINA_BASE is the location of the configuration files of this instance of Tomcat
export CATALINA_BASE=CATALINABASE
 
#TOMCAT_USER is the default user of tomcat
export TOMCAT_USER=tomcat
 
#TOMCAT_USAGE is the message if this script is called without any options
TOMCAT_USAGE="Usage: $0 {\e[00;32mstart\e[00m|\e[00;31mstop\e[00m|\e[00;31mkill\e[00m|\e[00;32mstatus\e[00m|\e[00;31mrestart\e[00m}"
 
#SHUTDOWN_WAIT is wait time in seconds for java proccess to stop
SHUTDOWN_WAIT=20
 
tomcat_pid() {
        echo `ps -fe | grep $CATALINA_BASE | grep -v grep | tr -s " "|cut -d" " -f2`
}
 
start() {
  pid=$(tomcat_pid)
  if [ -n "$pid" ]
  then
    echo -e "\e[00;31mTomcat is already running (pid: $pid)\e[00m"
  else
    # Start tomcat
    echo -e "\e[00;32mStarting tomcat\e[00m"
    #ulimit -n 100000
    #umask 007
    #/bin/su -p -s /bin/sh $TOMCAT_USER
        if [ `user_exists $TOMCAT_USER` = "1" ]
        then
                /bin/su $TOMCAT_USER -c $CATALINA_HOME/bin/startup.sh
        else
                sh $CATALINA_HOME/bin/startup.sh
        fi
        status
  fi
  return 0
}
 
status(){
          pid=$(tomcat_pid)
          if [ -n "$pid" ]; then echo -e "\e[00;32mTomcat is running with pid: $pid\e[00m"
          else echo -e "\e[00;31mTomcat is not running\e[00m"
          fi
}

terminate() {
	echo -e "\e[00;31mTerminating Tomcat\e[00m"
	kill -9 $(tomcat_pid)
}

stop() {
  pid=$(tomcat_pid)
  if [ -n "$pid" ]
  then
    echo -e "\e[00;31mStoping Tomcat\e[00m"
    #/bin/su -p -s /bin/sh $TOMCAT_USER
        sh $CATALINA_HOME/bin/shutdown.sh
 
    let kwait=$SHUTDOWN_WAIT
    count=0;
    until [ `ps -p $pid | grep -c $pid` = '0' ] || [ $count -gt $kwait ]
    do
      echo -n -e "\n\e[00;31mwaiting for processes to exit\e[00m";
      sleep 1
      let count=$count+1;
    done
 
    if [ $count -gt $kwait ]; then
      echo -n -e "\n\e[00;31mkilling processes didn't stop after $SHUTDOWN_WAIT seconds\e[00m"
      terminate
    fi
  else
    echo -e "\e[00;31mTomcat is not running\e[00m"
  fi
 
  return 0
}
 
user_exists(){
        if id -u $1 >/dev/null 2>&1; then
        echo "1"
        else
                echo "0"
        fi
}
 
case $1 in
	start)
	  start
	;;
	stop)  
	  stop
	;;
	restart)
	  stop
	  start
	;;
	status)
		status
	;;
	kill)
		terminate
	;;		
	*)
		echo -e $TOMCAT_USAGE
	;;
esac    
EOF
  )
  run "   - Creating /etc/init.d/tomcat${i}" "" "" 'echo "${tomcatInit}" > /etc/init.d/tomcat${i}'
  run "   - Configuring /etc/init.d/tomcat${i}" "" "" "sed -i s#JAVAHOME#${base}/java#g /etc/init.d/tomcat${i}" \
   "sed -i s#CATALINAHOME#${base}/tomcat/tomcat_${i}#g /etc/init.d/tomcat${i}" \
   "sed -i s#CATALINABASE#${base}/tomcat/tomcat_${i}#g /etc/init.d/tomcat${i}"
  run "   - Fixing permission of etc/init.d/tomcat${i}" "" "" "chmod 755 /etc/init.d/tomcat${i}"
  run "   - Adding to service" "" "" "chkconfig --add tomcat${i}"
  run "   - Configuring /opt/tomcat/tomcat_${i}/conf/tomcat-users.xml" "" "" "sed -i '/<\/tomcat-users>/ i \ \ <role rolename=\"manager-gui\" \/>' /opt/tomcat/tomcat_${i}/conf/tomcat-users.xml" \
   "sed -i '/<\/tomcat-users>/ i \ \ <role rolename=\"admin-gui\" \/>' /opt/tomcat/tomcat_${i}/conf/tomcat-users.xml" \
   "sed -i '/<\/tomcat-users>/ i \ \ <user username=\"admin\" password=\"P@ssw0rd\" roles=\"manager-gui,admin-gui\" \/>' /opt/tomcat/tomcat_${i}/conf/tomcat-users.xml"
  run "   - Configuring /opt/tomcat/tomcat_${i}/webapps/manager/META-INF/context.xml" "" "" "sed -i 's/allow=.*/allow=\"127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1|192.168.*.*\" \/>/g' /opt/tomcat/tomcat_${i}/webapps/manager/META-INF/context.xml"
  run "   - Configuring /opt/tomcat/tomcat_${i}/webapps/host-manager/META-INF/context.xml" "" "" "sed -i 's/allow=.*/allow=\"127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1|192.168.*.*\" \/>/g' /opt/tomcat/tomcat_${i}/webapps/host-manager/META-INF/context.xml"
  run "   - Configuring /opt/tomcat/tomcat_${i}/conf/server.xml" "" "" "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/,+1d' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/Connector protocol\=\"AJP\/1\.3\"/ i \ \ \ \ <\!-- Define an AJP 1.3 Connector on port 8009 -->' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/Connector protocol\=\"AJP\/1\.3/,+4d' /opt/tomcat/tomcat_$i/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ connectionTimeout\=\"60000\" \/>' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ maxThreads\=\"200\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ enableLookup\=\"false\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ secretRequired\=\"false\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ redirectPort\=\"8443\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ port\=\"'${pTomcatAJP}'\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ address\=\"::1\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -i '/<!-- Define an AJP 1.3 Connector on port 8009 -->/ a \ \ \ \ <Connector protocol=\"AJP/1.3\"' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -Ei 's#(Connector port=\")8080(\" protocol=\"HTTP/1.1\")#\1'${pTomcat}'\2#g' /opt/tomcat/tomcat_${i}/conf/server.xml" \
   "sed -Ei 's#(<Server port=\")8005(\" shutdown=\"SHUTDOWN\">)#\1'${pTomcatShut}'\2#g' /opt/tomcat/tomcat_${i}/conf/server.xml" 
  run "   - Stating instnace" "" "" "service tomcat${i} start"
 done
 workerConf=$(cat <<EOF
worker.list=lb,status
worker.status.type=status
worker.lb.type=lb
worker.lb.sticky_session=1
EOF
  )
 run " - Creating ${base}/httpd/conf/extra/workers.properties" "" "" 'echo "${workerConf}" > ${base}/httpd/conf/extra/workers.properties'
 nodes=""
 for i in `seq 1 ${tomcatInstance}`; do 
  if [ ${i} -eq ${tomcatInstance} ] ; then 
   nodes=${nodes}"node${i}"
  else
   nodes=${nodes}"node${i},"
  fi
 done

 run " - Configuring ${base}/httpd/conf/extra/workers.properties" "" "" "echo worker.lb.balance_workers=${nodes} >> ${base}/httpd/conf/extra/workers.properties"
 writeln " - Confguring tomcat tomcat instnace"
 for i in $(seq 1 ${tomcatInstance});  do
  let pTomcatAJP=${tomcatAJP}+${i}
  run "   - Adding tomcat instance to ${base}/httpd/conf/extra/workers.properties" "" "" "echo worker.node${i}.type=ajp13 >> ${base}/httpd/conf/extra/workers.properties" \
   "echo worker.node${i}.host=localhost >> ${base}/httpd/conf/extra/workers.properties" \
   "echo worker.node${i}.port=${pTomcatAJP} >> ${base}/httpd/conf/extra/workers.properties" \
   "echo worker.node${i}.lbfactor=1 >> ${base}/httpd/conf/extra/workers.properties" \
   "echo worker.node${i}.cachesize=10 >> ${base}/httpd/conf/extra/workers.properties"
 done
 jkConf=$(cat <<-EOF 
JkWorkersFile ${base}/httpd/conf/extra/workers.properties
JkShmFile     ${base}/httpd/logs/mod_jk.shm
JkLogFile     ${base}/httpd/logs/mod_jk.log
JkLogLevel    error
JkLogStampFormat "[%a %b %d %H:%M:%S %Y] "
JkMount  /examples/* lb
JkMount  /status status
EOF
 )
 run " - Configuring ${base}/httpd/conf/extra/jk_modules.conf" "" "" 'echo "${jkConf}" >> ${base}/httpd/conf/extra/jk_modules.conf'
 run " - Restarting httpd" "" "" "service httpd restart"
 writeln ""
}

function test () 
{
 writeln "Test Tomcat"
 for f in $(seq 1 ${tomcatInstance}); do
  let p=${tomcatPort}+${f}
  result=1
  writeln "Running curl http://127.0.0.1:${p}/examples/servlets/servlet/HelloWorldExample"
  writeln "------------------------------------------------------------------------------------------------------"
  while [ ${result} -ne 0 ] ; 
   do
    curl http://127.0.0.1:${p}/examples/servlets/servlet/HelloWorldExample >/dev/null 2>&1
    result=$?
    if [ ${result} -ne 0 ]; then
     writeln "tomcat not initialized. Retry in next 10s..."  
     sleep 10 
    else
     writeln ""
     writeln "Result:"
     writeln "$(curl http://127.0.0.1:${p}/examples/servlets/servlet/HelloWorldExample)"
     writeln ""
    fi
   done 
 done

 writeln "Test AJP"
 writeln "Running curl http://127.0.0.1/examples/servlets/servlet/HelloWorldExample"
 writeln "------------------------------------------------------------------------------------------------------"
  writeln "Result:"
 writeln "$(curl http://127.0.0.1/examples/servlets/servlet/HelloWorldExample)"
 writeln ""
 writeln "Running ${base}/httpd/bin/ab -n ${requests} -c ${concurrent} http://127.0.0.1/examples/servlets/servlet/HelloWorldExample"
 writeln "------------------------------------------------------------------------------------------------------"
 writeln "$(${base}/httpd/bin/ab -n ${requests} -c ${concurrent} http://127.0.0.1/examples/servlets/servlet/HelloWorldExample)"
 writeln  ""
 writeln "Running  curl http://127.0.0.1/status?mime=txt"
 writeln "------------------------------------------------------------------------------------------------------"
 writeln "$(curl http://127.0.0.1/status?mime=txt)"
 writeln ""
}

function cleanupTomcat ()
{
  writeln "Cleanup Tomcat"
  for f in $(chkconfig --list 2>/dev/null | grep -Eo tomcat[0-9]+); do    
   writeln " - Cleanup tomcat instance ${f}"
   run "   - Stopping service" "" "" "service ${f} stop"
   run "   - Remove service " "" "" "chkconfig --del ${f}"
   run "   - Remove service file /etc/init.d/${f}" "" "" "rm -f /etc/init.d/${f}"
   instance=$(echo $f | sed 's/tomcat//g')
   run "   - Removing symlink" "" "" "unlink ${base}/tomcat/tomcat_${instance}"
   run "   - Removing files" "" "" "rm -fr ${base}/tomcat/apache-tomcat*_${instnace}"
  done
  run " - Removing ${base}/tomcat" "" "" "rm -fr ${base}/tomcat"
  writeln ""
}

function cleanupModJK ()
{
 writeln "Cleanup ModJK"
 run " - Removing config file ${base}/httpd/conf/extra/jk_modules.conf" "" "" "rm -f ${base}/httpd/conf/extra/jk_modules.conf"
 run " - Removing workers defination ${base}/httpd/conf/extra/workers.properties" "" "" "rm -f ${base}/httpd/conf/extra/workers.properties"
 run " - Removing module ${base}/httpd/modules/mod_jk.so" "" "" "rm -f ${base}/httpd/modules/mod_jk.so"
 run " - Restart httpd" "" "" "service httpd restart"
 writeln ""
}

function cleanupHttpd ()
{
 writeln "Cleanup Httpd"
 run " - Stopping httpd" "" "" "service httpd stop"
 run " - Removing service httpd" "" "" "chkconfig --del httpd"
 run " - Removing service definaion" "" "" "rm -f /etc/init.d/httpd"
 run " - Removing config file /etc/sysconfig/httpd" "" "" "rm -f /etc/sysconfig/httpd"
 run " - Removing binaries" "" "" "rm -fr ${base}/httpd"
 writeln ""
}

function cleanupJDK ()
{
 writeln "Cleanup JDK"
 run " - Removing symlink" "" "" "unlink ${base}/java"
 run " - Removing binaries" "" "" "rm -fr ${base}/jdk-*"
 writeln ""
}

function cleanupApr ()
{
 writeln "Cleanup APR"
 run " - Removing binaries" "" "" "rm -fr ${base}/apr"
 writeln ""
}

function cleanupTmp ()
{
 writeln "Cleanup temporary folder"
 run " - Removing temporary files" "" "" "rm -fr ${tmpFolder}"
 writeln ""
}

function init ()
{
 writeln "Initialization..." "log"
 run " - Creating folder ${tmpFolder} if not exist" "" "" "mkdir -p ${tmpFolder}"
 run " - Creating folder ${srcFolder} if not exist" "" "" "mkdir -p ${srcFolder}"
 run " - Creating folder ${base} if not exist" "" "" "mkdir -p ${base}"
 writeln ""
}

function usage ()
{
 echo "Usage: ${0} [Action]"
 echo "  Actions:   compileApr                     - compile apache runtime and apache runtime utils"
 echo "             compileHttpd                   - compiled httpd"
 echo "             compileModJK                   - compile mod jk"
 echo "             installJDK                     - install JDK"
 echo "             installTomcat [instance]       - install tomcat"
 echo "                   instance                 - install XX instnace, default is ${tomcatInstance}"
 echo "             installAll [instnace]          - install apache runtime, apache runtime utils, httpd, mod jk, JDK, and tomcat"
 echo "                   instance                 - install XX instnace, default is ${tomcatInstance}"
 echo "             test [request] [concurrent]    - test the whole installation using ab"
 echo "                   request                  - total request to beexecuted, default is ${requests}"
 echo "                   concurrent               - concurrent reqests, default is ${concurrent}"
 echo "             cleanupTomcat                  - remove tomcat"
 echo "             cleanupModJK                   - remove mod jk"
 echo "             cleanupJDK                     - remove JDK"
 echo "             cleanupHttpd                   - remove httpd"
 echo "             cleanupApr                     - remove apache runtime and apache runtime utils"
 echo "             cleanupTmp                     - remove tmp folder"
 echo "             cleanupAll                     - remove tomcat, mod jk, JDK, httpd, apache runtime, apache runtime utils and tmp folder"
 exit 1
}

function main ()
{
 case "${1}" in
  compileApr)
   init
   compileApr
   compileAprUtil
   ;;
  compileHttpd)
   init
   compileHttpd
   ;;
  compileModJk)
   init
   compileModJK
   ;;
  installJDK)
   init
   installJDK
   ;;
  installTomcat)
   init
   [[ ! -z "${2}" ]] && tomcatInstance=${2}
   installTomcat
   ;;
  installAll)
   [[ ! -z "${2}" ]] && tomcatInstance=${2}
   init
   compileApr
   compileAprUtil
   compileHttpd
   compileModJK
   installJDK
   installTomcat
   cleanupTmp
   ;;
  test)
   [[ ! -z "${2}" ]] && requests=${2}
   [[ ! -z "${3}" ]] && concurrent=${3}
   test
   ;;
  cleanupTomcat)
   cleanupTomcat
   ;;
  cleanupModJK)
   cleanupModJK
   ;;
  cleanupJDK)
   cleanupJDK
   ;;
  cleanupHttpd)
   cleanupHttpd
   ;;
  cleanupApr)
   cleanupApr
   ;;
  cleanupTmp)
   cleanupTmp
   ;;
  cleanupAll)
   cleanupTomcat
   cleanupModJK
   cleanupJDK
   cleanupHttpd
   cleanupApr
   cleanupTmp
   ;;
  *) 
   usage
  ;;
 esac
}

main ${*}

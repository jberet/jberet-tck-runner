#!/bin/bash
set -x

err_report() {
  echo "Error on line $1"
  exit 1
}

trap 'err_report $LINENO' ERR

BATCH_TCK_VER=${SET_BATCH_TCK_VER:-2.1.1}

wget https://download.eclipse.org/jakartaee/batch/2.1/jakarta.batch.official.tck-${BATCH_TCK_VER}.zip
unzip jakarta.batch.official.tck-${BATCH_TCK_VER}.zip
export BATCH_TCK_DIR=$(pwd)/jakarta.batch.official.tck-${BATCH_TCK_VER}

# We need to build a customized `batch-tck` branch that disables the Java versions enforcer rule and disable the `sigtest` module build.
#git clone https://github.com/liweinan/batch-tck.git
#pushd batch-tck
#git checkout disable_jdk_checking_and_sigtest_build
#mvn install -DskipTests
#echo "build batch-tck result: $?"
#popd

git clone https://github.com/scottkurz/batch-tck.git
pushd batch-tck
git checkout use-jakarta-tck-sigtest
mvn install -DskipTests
popd


# Use the customized branch to override the `batch-tck` version.
git clone https://github.com/liweinan/jberet-tck-porting.git

# build for jdk 21 testings
pushd jberet-tck-porting
git checkout switch_sigtest_maven_plugin
mvn install -DskipTests
echo "build jberet-tck-porting result: $?"
popd

export JBERET_PORTING_DIR=$(pwd)/jberet-tck-porting

git clone https://github.com/jberet/jsr352.git

pushd jsr352
mvn install -DskipTests
echo "build jsr352 result: $?"
jberet_ver=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
popd

cp $JBERET_PORTING_DIR/src/main/resources/runners/sigtest/pom.xml $BATCH_TCK_DIR/runners/sigtest/pom.xml
cp $JBERET_PORTING_DIR/src/main/resources/runners/se-classpath/pom.xml $BATCH_TCK_DIR/runners/se-classpath/pom.xml
cp $JBERET_PORTING_DIR/src/main/resources/runners/platform-arquillian/pom.xml $BATCH_TCK_DIR/runners/platform-arquillian/pom.xml
cp $JBERET_PORTING_DIR/src/main/resources/runners/platform-arquillian/src/test/resources/arquillian.xml $BATCH_TCK_DIR/runners/platform-arquillian/src/test/resources/arquillian.xml

# Run sigtest
pushd $BATCH_TCK_DIR/runners/sigtest
mvn install -Dversion.org.jberet.jberet-core=${jberet_ver}
echo "run sigtest result: $?"
popd

# Run SE tests
pushd $BATCH_TCK_DIR/runners/se-classpath
mvn install -Dversion.org.jberet.jberet-core=${jberet_ver}
echo "se-classpath running result: $?"
popd


WFLY_VER=$(curl --silent -qI https://github.com/wildfly/wildfly/releases/latest | grep '^location.*' | tr -d '\r')
WFLY_VER=${WFLY_VER##*/}

wget https://github.com/wildfly/wildfly/releases/download/${WFLY_VER}/wildfly-${WFLY_VER}.zip
unzip wildfly-${WFLY_VER}.zip

export JBOSS_HOME=$(pwd)/wildfly-${WFLY_VER}

cp $JBERET_PORTING_DIR/target/jberet-tck-porting.jar $JBOSS_HOME/standalone/deployments/

# Run integration tests

# start WildFly server
pushd $JBOSS_HOME/bin
./standalone.sh &

sleep 10
NUM=0
while true
do
NUM=$[$NUM + 1]
if (("$NUM" > "6")); then
    echo "Application server failed to start up!"
    exit 1
fi

if ./jboss-cli.sh --connect command=':read-attribute(name=server-state)' | grep running; then
    echo "server is running"
    break
fi
    echo "server is not yet running"
    sleep 10
done
popd

pushd $BATCH_TCK_DIR/runners/platform-arquillian
mvn install
echo "platform-arquillian running result: $?"
popd

# stop WildFly server
$JBOSS_HOME/bin/jboss-cli.sh --connect --commands="undeploy jberet-tck-porting.jar, shutdown"
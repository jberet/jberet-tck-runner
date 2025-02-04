#!/bin/bash
set -x

err_report() {
  echo "Error on line $1"
  exit 1
}

trap 'err_report $LINENO' ERR

# clone the upstream `batch-tck` and build it.
rm -rf batch-tck
git clone --depth 1 https://github.com/jakartaee/batch-tck.git
pushd batch-tck
git checkout master
# https://github.com/jakartaee/batch-tck/issues/77
mvn clean install -DskipTests -Dxml.skip -Decho.skip
BATCH_TCK_VER=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
popd

export BATCH_TCK_DIR=$(pwd)/batch-tck

# Use the customized branch to override the `batch-tck` version.
rm -rf jberet-tck-porting
git clone --depth 1 https://github.com/jberet/jberet-tck-porting.git

# build for jdk 21 testings
pushd jberet-tck-porting
git checkout main
mvn install -DskipTests
echo "build jberet-tck-porting result: $?"
popd

export JBERET_PORTING_DIR=$(pwd)/jberet-tck-porting

rm -rf jsr352
git clone --depth 1 https://github.com/jberet/jsr352.git

if [ "${USE_BRANCH}" != "" ]; then
  echo "Using the JBeret branch ${USE_BRANCH} for testings."
  pushd jsr352
  git remote set-branches --add origin "${USE_BRANCH}"
  git fetch origin "${USE_BRANCH}"
  git checkout "${USE_BRANCH}"
  git branch -a
  popd
fi

pushd jsr352
mvn install -DskipTests
echo "build jsr352 result: $?"
jberet_ver=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
popd

cp $JBERET_PORTING_DIR/src/main/resources/runners/sigtest/pom-parent-param.xml $BATCH_TCK_DIR/com.ibm.jbatch.tck.sigtest.exec/pom.xml
cp $JBERET_PORTING_DIR/src/main/resources/runners/se-classpath/pom-parent-param.xml $BATCH_TCK_DIR/com.ibm.jbatch.tck.exec/pom.xml
cp $JBERET_PORTING_DIR/src/main/resources/runners/platform-arquillian/pom-parent-param.xml $BATCH_TCK_DIR/jakarta.batch.arquillian.exec/pom.xml
cp $JBERET_PORTING_DIR/src/main/resources/runners/platform-arquillian/src/test/resources/arquillian.xml $BATCH_TCK_DIR/jakarta.batch.arquillian.exec/src/test/resources/arquillian.xml

sed -ie "s/BATCH_PARENT_VER/${BATCH_TCK_VER}/g" $BATCH_TCK_DIR/com.ibm.jbatch.tck.sigtest.exec/pom.xml
sed -ie "s/BATCH_PARENT_VER/${BATCH_TCK_VER}/g" $BATCH_TCK_DIR/com.ibm.jbatch.tck.exec/pom.xml
sed -ie "s/BATCH_PARENT_VER/${BATCH_TCK_VER}/g" $BATCH_TCK_DIR/jakarta.batch.arquillian.exec/pom.xml

# Run sigtest
echo "start to run sigtest"
pushd $BATCH_TCK_DIR/com.ibm.jbatch.tck.sigtest.exec
mvn install -Dversion.org.jberet.jberet-core=${jberet_ver}
echo "run sigtest result: $?"
popd

# Run SE tests
echo "start to run SE tests"
pushd $BATCH_TCK_DIR/com.ibm.jbatch.tck.exec
mvn install -Dversion.org.jberet.jberet-core=${jberet_ver}
echo "se-classpath running result: $?"
popd

USE_PROFILE="${USE_PROFILE}" \
WFLY_VER="${WFLY_VER}" \
JBERET_VER="${jberet_ver}" \
BATCH_TCK_DIR="${BATCH_TCK_DIR}" \
./run-wildfly-ci.sh

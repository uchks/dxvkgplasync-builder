#!/usr/bin/env bash

opt_nopackage=0
opt_devbuild=0
opt_deploy_web=0
opt_force=0
opt_nobuild=0
opt_gitlab=0
opt_github=0
opt_buildid=false

build_args="master ../build/ --no-package"

PATCH_FILE="dxvk-gplasync-master.patch"
DXVK_ASYNC_MIRROR="https://gitlab.com/Ph42oN/dxvk-gplasync"
DXVK_ASYNC_BRANCH="main"

while [ $# -gt 0 ]; do
  case "$1" in
  "--no-package")
    opt_nopackage=1
    ;;
  "--dev-build")
    opt_nopackage=1
    opt_devbuild=1
    build_args+=" --dev-build"
    ;;
  "--build-id")
    opt_buildid=false
    build_args+=" --build-id"
    ;;
  "--no-build")
    opt_nobuild=1
    ;;
  "--force")
    opt_force=1
    ;;
  "--deploy-web")
    opt_deploy_web=1
    ;;
  "--gitlab")
    opt_gitlab=1
    ;;
  "--github")
    opt_github=1
    ;;
  *)
    echo "Unrecognized option: $1" >&2
    exit 1
  esac
  shift
done

update_dxvk() {
  if [ ! -d "./dxvk" ]; then
    git clone --depth 1 --branch master https://github.com/doitsujin/dxvk
  fi
  cd ./dxvk
  echo "Reverting file changes (in case already patched with DXVK-Async)..."
  git reset --hard
  echo "Updating DXVK..."
  git pull
  git submodule update --init --recursive
  dxvk_commit=$(git rev-parse --short HEAD)
  dxvk_long_commit=$(git rev-parse HEAD)
  dxvk_branch=$(git rev-parse --abbrev-ref HEAD)
  cd ..
}

update_dxvk_async() {
  if [ ! -d "./dxvk-async" ]; then
    git clone --depth 1 $DXVK_ASYNC_MIRROR dxvk-async
  fi
  cd ./dxvk-async
  echo "Reverting file changes..."
  git reset --hard
  echo "Updating DXVK-Async..."
  git pull
  git switch $DXVK_ASYNC_BRANCH
  dxvk_async_commit=$(git rev-parse --short HEAD)
  dxvk_async_long_commit=$(git rev-parse HEAD)
  dxvk_async_branch=$(git rev-parse --abbrev-ref HEAD)
  cd ..
}

patch_dxvk() {
  if [ -d "./dxvk" ]; then
    # echo "Fixing dxvk-gplasync patches..."
    # cd ./dxvk-async
    # git apply --reject --whitespace=fix ../patches/dxvk-gplasync.patch
    # echo "Fix complete."
    # cd ../dxvk
    cd ./dxvk
    echo "Patching DXVK..."
    if [[ $opt_github == 1 ]] && [[ $opt_force == 1 ]]; then
      echo "!!! FORCING BUILD EVEN PATCH FAILS CAN CAUSE ERROR IN DXVK !!!"
      echo "Applying GitHub workaround..."
      git apply --reject --whitespace=fix ../dxvk-async/patches/$PATCH_FILE &
      git apply --reject --whitespace=fix ../dxvk-async/patches/global-dxvk.conf.patch &
      sleep 5
      echo "Workaround completed."
    else
      git apply --reject --whitespace=fix ../dxvk-async/patches/$PATCH_FILE
      ret_val=$?
      if [ $ret_val -ne 0 ]; then
        echo "Patch error, exiting..."
        echo "This is most likely caused by the patch itself."
        echo "Consider reporting at: $DXVK_ASYNC_MIRROR"
        if [[ $opt_force == 1 ]]; then
          echo "!!! FORCING BUILD EVEN PATCH FAILS CAN CAUSE ERROR IN DXVK !!!"
        else
          exit $ret_val
        fi
      fi
      git apply --reject --whitespace=fix ../dxvk-async/patches/global-dxvk.conf.patch
    fi
    cd ..
  fi
}

build_dxvk() {
  if [ -d "./dxvk" ]; then
    cd ./dxvk
    echo "Building DXVK-Async... (args: $build_args)"
    rm -rf "./dxvk-master"
    ./package-release.sh $build_args
    cd ../build
    rm -rf "./$package_name"
    mv "./dxvk-master" "./$package_name"
    cd ..
  fi
}

pack_dxvk() {
  echo "Packing..."
  cd ./build
  tar -czf "$package_name.tar.gz" "./$package_name"
  sha256=$(sha256sum "$package_name.tar.gz" | cut -d " " -f 1)
  echo "SHA256: $sha256"
  cd ..
}

pack_web_dxvk() {
  echo "Setting DXVK url in webpage..."
  cd ./build/
  cp -r ../web ./web/
  cd ./web/
  mv index.html index.html.bak
  sed -e "s/{GIT_DXVK_BRANCH}/$dxvk_branch/g" -e "s/{GIT_DXVK_SHORT_COMMIT_HASH}/$dxvk_commit/g" -e "s/{GIT_DXVK_COMMIT_HASH}/$dxvk_long_commit/g" \
      -e "s/{GIT_DXVK_ASYNC_BRANCH}/$dxvk_async_branch/g" -e "s/{GIT_DXVK_ASYNC_SHORT_COMMIT_HASH}/$dxvk_async_commit/g" -e "s/{GIT_DXVK_ASYNC_COMMIT_HASH}/$dxvk_async_long_commit/g" \
      -e "s/{FILE_NAME}/$package_name.tar.gz/g" -e "s/{FILE_SHA}/$sha256/g" \
  index.html.bak > index.html

  mv gitlab_dl.html gitlab_dl.html.bak
  sed -e "s/{FILE_NAME}/$package_name.tar.gz/g" gitlab_dl.html.bak > gitlab_dl.html
  
  mv github_dl.html github_dl.html.bak
  sed -e "s/{FILE_NAME}/$package_name.tar.gz/g" -e "s/{PACKAGE_NAME}/$package_name/g" github_dl.html.bak > github_dl.html

  mv api/build.json api/build.json.bak
  sed -e "s/{GIT_DXVK_BRANCH}/$dxvk_branch/g" -e "s/{GIT_DXVK_SHORT_COMMIT_HASH}/$dxvk_commit/g" -e "s/{GIT_DXVK_COMMIT_HASH}/$dxvk_long_commit/g" \
      -e "s/{GIT_DXVK_ASYNC_BRANCH}/$dxvk_async_branch/g" -e "s/{GIT_DXVK_ASYNC_SHORT_COMMIT_HASH}/$dxvk_async_commit/g" -e "s/{GIT_DXVK_ASYNC_COMMIT_HASH}/$dxvk_async_long_commit/g" \
      -e "s/{FILE_NAME}/$package_name.tar.gz/g" -e "s/{FILE_SHA}/$sha256/g" -e "s/{PACKAGE_NAME}/$package_name/g" \
  api/build.json.bak > api/build.json

  rm -f *.bak
  mkdir -p ./build/
  cp "../$package_name.tar.gz" "./build/$package_name.tar.gz"
}

pack_api_dxvk() {
  echo "Generating fake API..."
  sed -e "s/{GIT_DXVK_BRANCH}/$dxvk_branch/g" -e "s/{GIT_DXVK_SHORT_COMMIT_HASH}/$dxvk_commit/g" -e "s/{GIT_DXVK_COMMIT_HASH}/$dxvk_long_commit/g" \
      -e "s/{GIT_DXVK_ASYNC_BRANCH}/$dxvk_async_branch/g" -e "s/{GIT_DXVK_ASYNC_SHORT_COMMIT_HASH}/$dxvk_async_commit/g" -e "s/{GIT_DXVK_ASYNC_COMMIT_HASH}/$dxvk_async_long_commit/g" \
      -e "s/{FILE_NAME}/$package_name.tar.gz/g" -e "s/{FILE_SHA}/$sha256/g" -e "s/{PACKAGE_NAME}/$package_name/g" \
  web/api/build.json > build.json
}

pack_changelog_dxvk() {
  sed -e "s/{GIT_DXVK_BRANCH}/$dxvk_branch/g" -e "s/{GIT_DXVK_SHORT_COMMIT_HASH}/$dxvk_commit/g" -e "s/{GIT_DXVK_COMMIT_HASH}/$dxvk_long_commit/g" \
      -e "s/{GIT_DXVK_ASYNC_BRANCH}/$dxvk_async_branch/g" -e "s/{GIT_DXVK_ASYNC_SHORT_COMMIT_HASH}/$dxvk_async_commit/g" -e "s/{GIT_DXVK_ASYNC_COMMIT_HASH}/$dxvk_async_long_commit/g" \
      -e "s/{FILE_NAME}/$package_name.tar.gz/g" -e "s/{FILE_SHA}/$sha256/g" -e "s/{PACKAGE_NAME}/$package_name/g" \
  INFO.md.template > INFO.md
}

update_dxvk
update_dxvk_async
package_name="dxvk-async-git+$dxvk_commit-git+$dxvk_async_commit"
if [[ $opt_gitlab == 1 ]]; then
  # GitLab workaround because compiling takes 30 minutes :D
  echo "GitLab mode."
  api=$(curl -s https://tretrauit.gitlab.io/dxvk-async-builder/api/build.json)
  if [[ $api == *"$package_name.tar.gz"* ]]; then
    echo "Already built, patching web instead..."
    mkdir -p ./build
    cd ./build
    echo "Downloading artifact..."
    curl -OL "https://tretrauit.gitlab.io/dxvk-async-builder/build/$package_name.tar.gz"
    sha256=$(sha256sum "$package_name.tar.gz" | cut -d " " -f 1)
    cd ..
    pack_web_dxvk
    exit 0
  fi
fi
if [[ $opt_github == 1 ]]; then
  echo "GitHub mode."
  api=$(curl -s https://api.github.com/repos/teppyboy/dxvk-async-builder/releases/latest)
  if [[ $api == *"$package_name"* ]]; then
    echo "Already built, patching web instead..."
    mkdir -p ./build
    cd ./build
    echo "Downloading artifact..."
    curl -OL "https://github.com/teppyboy/dxvk-async-builder/releases/download/$package_name/$package_name.tar.gz"
    sha256=$(sha256sum "$package_name.tar.gz" | cut -d " " -f 1)
    cd ..
    export PACKAGE_NAME=$package_name
    pack_changelog_dxvk
    pack_api_dxvk
    return 0
  fi
fi
if [[ $opt_nobuild == 0 ]]; then
  patch_dxvk
  build_dxvk
fi
if [[ $opt_nopackage == 0 ]]; then
  pack_dxvk
  if [[ $opt_github == 1 ]]; then
    export PACKAGE_NAME=$package_name
    pack_changelog_dxvk
    pack_api_dxvk
  fi
  if [[ $opt_deploy_web == 1 ]]; then
    pack_web_dxvk
  fi
fi
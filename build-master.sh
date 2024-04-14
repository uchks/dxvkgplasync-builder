#!/usr/bin/env bash

declare -A options=(
  [no_package]=0
  [dev_build]=0
  [deploy_web]=0
  [force]=0
  [no_build]=0
)

build_args="master ../build/ --no-package"
PATCH_FILE="dxvk-gplasync-master.patch"
DXVK_ASYNC_MIRROR="https://gitlab.com/Ph42oN/dxvk-gplasync"
DXVK_ASYNC_BRANCH="main"

for arg in "$@"; do
  case "$arg" in
    "--no-package") options[no_package]=1 ;;
    "--dev-build") 
      options[no_package]=1
      options[dev_build]=1
      build_args+=" --dev-build"
      ;;
    "--build-id") build_args+=" --build-id" ;;
    "--no-build") options[no_build]=1 ;;
    "--force") options[force]=1 ;;
    "--deploy-web") options[deploy_web]=1 ;;
    *) echo "Unrecognized option: $arg" >&2; exit 1 ;;
  esac
done

update_dxvk() {
  local dir="./dxvk"
  [[ -d $dir ]] || git clone --depth 1 --branch master https://github.com/doitsujin/dxvk $dir
  pushd $dir
  git reset --hard
  git pull
  git submodule update --init --recursive
  dxvk_commit=$(git rev-parse --short HEAD)
  dxvk_long_commit=$(git rev-parse HEAD)
  dxvk_branch=$(git rev-parse --abbrev-ref HEAD)
  popd
}

update_dxvk_async() {
  local dir="./dxvk-gplasync"
  [[ -d $dir ]] || git clone --depth 1 $DXVK_ASYNC_MIRROR $dir
  pushd $dir
  git reset --hard
  git pull
  git switch $DXVK_ASYNC_BRANCH
  dxvk_async_commit=$(git rev-parse --short HEAD)
  dxvk_async_long_commit=$(git rev-parse HEAD)
  dxvk_async_branch=$(git rev-parse --abbrev-ref HEAD)
  popd
}

patch_dxvk() {
  if [[ -d "./dxvk" && ${options[no_build]} -eq 0 ]]; then
    pushd "./dxvk"
    echo "Patching DXVK..."
    git apply --reject --whitespace=fix ../dxvk-gplasync/patches/$PATCH_FILE || {
      echo "Patch failed, consider reporting at: $DXVK_ASYNC_MIRROR"
      [[ ${options[force]} -eq 1 ]] || exit 1
    }
    popd
  fi
}

build_dxvk() {
  if [[ -d "./dxvk" && ${options[no_build]} -eq 0 ]]; then
    pushd "./dxvk"
    echo "Building dxvk-gplasync... (args: $build_args)"
    ./package-release.sh $build_args
    popd
  fi
}

pack_dxvk() {
  if [[ ${options[no_package]} -eq 0 ]]; then
    echo "Packing..."
    pushd "./build"
    tar -czf "$package_name.tar.gz" "./$package_name"
    sha256=$(sha256sum "$package_name.tar.gz" | cut -d " " -f 1)
    echo "SHA256: $sha256"
    popd
  fi
}

pack_web_dxvk() {
  if [[ ${options[deploy_web]} -eq 1 ]]; then
    echo "Setting DXVK url in webpage and preparing for GitHub Pages deployment..."
    mkdir -p ./build/web
    cp -r ./web/* ./build/web/
    pushd ./build/web
    sed -i.bak -e "s/{GIT_DXVK_BRANCH}/$dxvk_branch/g" \
               -e "s/{GIT_DXVK_SHORT_COMMIT_HASH}/$dxvk_commit/g" \
               -e "s/{GIT_DXVK_COMMIT_HASH}/$dxvk_long_commit/g" \
               -e "s/{GIT_DXVK_ASYNC_BRANCH}/$dxvk_async_branch/g" \
               -e "s/{GIT_DXVK_ASYNC_SHORT_COMMIT_HASH}/$dxvk_async_commit/g" \
               -e "s/{GIT_DXVK_ASYNC_COMMIT_HASH}/$dxvk_async_long_commit/g" \
               -e "s/{FILE_NAME}/$package_name.tar.gz/g" \
               -e "s/{FILE_SHA}/$sha256/g" \
               index.html
    rm *.bak
    popd
    echo "Web files are prepared for deployment at ./build/web"
  fi
}

update_dxvk
update_dxvk_async
package_name="dxvk-gplasync-git+$dxvk_commit-git+$dxvk_async_commit"
patch_dxvk
build_dxvk
pack_dxvk
pack_web_dxvk
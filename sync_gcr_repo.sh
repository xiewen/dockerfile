#!/bin/bash

p()
{
  echo "$(date '+%Y-%m-%d %H:%M:%S.%N') $*"
}



add_yum_repo()
{
  cat > /etc/yum.repos.d/google-cloud-sdk.repo <<'EOF'
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
}

add_apt_source()
{
  export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
  echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
}

install_sdk()
{
    local OS_VERSION=$(grep -Po '(?<=^ID=")\w+' /etc/os-release)
    local OS_VERSION=${OS_VERSION:-ubuntu}
    if [[ $OS_VERSION =~ "centos" ]];then
        if ! [ -f /etc/yum.repos.d/google-cloud-sdk.repo ];then
            add_yum_repo
            yum -y install google-cloud-sdk
        else
            echo "gcloud is installed"
        fi
    elif [[ $OS_VERSION =~ "ubuntu" ]];then
        if ! [ -f /etc/apt/sources.list.d/google-cloud-sdk.list ];then
            add_apt_source
            sudo apt-get -y update && sudo apt-get -y install google-cloud-sdk
        else
             echo "gcloud is installed"
        fi
    fi
}


#https://stackoverflow.com/questions/28320134/how-can-i-list-all-tags-for-a-docker-image-on-a-remote-registry
get_hub_token()
{
  declare -r item=$1
  declare -r tokenUri="https://auth.docker.io/token"
  declare -a data=("service=registry.docker.io" "scope=repository:$item:pull")
  declare -a -r cmd=(
    curl --silent --get
    --data-urlencode "${data[0]}"
    --data-urlencode "${data[1]}"
    "$tokenUri"
  )
  "${cmd[@]}" | jq --raw-output '.token'
}
get_hub_tags()
{
  declare -r item=$1
  declare -r listUri="https://registry-1.docker.io/v2/$item/tags/list"
  declare token
  token=$(get_hub_token "$item")
  declare -a -r cmd=(
    curl --silent --get
    -H "Accept: application/json"
    -H "Authorization: Bearer $token"
    "$listUri"
  )
  # https://stackoverflow.com/questions/42097410/how-to-check-for-presence-of-key-in-jq-before-iterating-over-the-values
  "${cmd[@]}" | jq --raw-output '.tags[]?' | sort --version-sort -k1,1 -r
}
# get_hub_tags xiewen/gcr.io_google-containers_kube-apiserver
# get_hub_tags xiewen/nnnnnn


get_gcr_tags()
{
  gcloud container images list-tags "$1" --filter="tags:*" --format=json \
    | jq -r '.[].tags[] '                                                \
    | grep -v -E "(-rc|-beta|-alpha)"                                    \
    | sort --version-sort -k1,1 -r                                       \
    | head -n3
}

sync_image()
{
  declare -r gcr_image_name=$1
  declare -r dockerhub_namespace=${2:-xiewen}
  declare -r hub_image_name=$dockerhub_namespace/${gcr_image_name//\//_}
  declare gcr_image
  declare dockerhub_image
  declare tag
  declare gcr_tags
  declare hub_tags
  declare diff_tags
  gcr_tags=$(get_gcr_tags "$gcr_image_name")
  hub_tags=$(get_hub_tags "$hub_image_name")
  diff_tags=$(
    echo "$gcr_tags" "$hub_tags" "$hub_tags" \
    | sed 's/[[:space:]]\+/\n/'              \
    | sed '/^$/d'                            \
    | sort                                   \
    | uniq -u                                \
    | sort --version-sort -k1,1 -r
  )
  #p "gcr_tags=$gcr_tags"
  #p "hub_tags=$hub_tags"
  #p "diff=$diff_tags"
  if [[ -z "$diff_tags" ]]; then
    p "$gcr_image_name: no diff"
    return
  fi
  while read tag
  do
    gcr_image=$gcr_image_name:$tag
    hub_image=$hub_image_name:$tag
    p "$gcr_image -> $hub_image"
    skopeo --insecure-policy copy "docker://$gcr_image" "docker://$hub_image"
  done <<<"$diff_tags"
}

# sync_image gcr.io/google-containers/kube-apiserver
# sync_image gcr.io/google-containers/kube-apiserverss
# sync_image gcr.io/google-containers/kube-haproxy

sync_gcr_to_hub()
{
  grep -v -E -- '-(arm|arm64|ppc64le|s390x|alpha)$' repo_list.txt \
  | sed '/^#/d;/^[[:space:]]*$/d' \
  | while read gcr_repo
  do
    sync_image "$gcr_repo"
  done
}

sync_gcr_to_hub

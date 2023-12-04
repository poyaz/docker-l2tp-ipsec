#!/usr/bin/env bash

DIRNAME=$(realpath "$0" | rev | cut -d'/' -f2- | rev)
readonly DIRNAME

if ! command -v yq &> /dev/null
then
    echo "Please install 'yq' in your operation system"
    exit 1
fi

prefix_image_l2tp_ipsec="poyaz/l2tp-ipsec"

l2tp_ipsec_version=$(yq -r '.version.l2tp-ipsec' .config.yaml)

cd "${DIRNAME}/docker/images/l2tp-ipsec" || exit 1
docker build -t "${prefix_image_l2tp_ipsec}:${l2tp_ipsec_version}" .
docker build -t "${prefix_image_l2tp_ipsec}:latest" .

cd "${DIRNAME}" || exit 1

docker push "${prefix_image_l2tp_ipsec}:${l2tp_ipsec_version}"
docker push "${prefix_image_l2tp_ipsec}:latest"

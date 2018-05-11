#!/bin/bash
# Ensure we fail the job if any steps fail
set -e -o pipefail

# Required parameters:
#
#  VERSION: Set this value based on the VERSION file in the project root.
#  DEPLOY_TYPE: Can be `snapshot`, `staging` or`release`
#    `snapshot` will push docker images to:
#       1) nexus3.edgexfoundry.org:10003 with a GIT_SHA-VERSION tag
#    `staging` will push docker images to:
#       1) nexus3.edgexfoundry.org:10004 with the `latest` tag
#       2) edgexfoundry dockerhub with the `latest` tag
#    `release` will push docker images to:
#       1) nexus3.edgexfoundry.org:10002 with the `latest` tag and `VERSION` tag
#       2) edgexfoundry dockerhub with the `latest` tag and `VERSION` tag
#
if [[ "X$NODE_NAME" == "Xcavium-arm64" ]]; then
  ARCH=-arm64
else
  ARCH=''
fi

GIT_SHA=$(git rev-parse --short HEAD)
VERSION=$(cat VERSION)
## Query build docker images, retag and push to respective repos based on DEPLOY_TYPE
images=( $(docker images --format "{{.Repository}}:{{.ID}}" --filter "label=git_sha=$GIT_SHA" | grep 'edgexfoundry.*-go' | sort -u))
for image in "${images[@]}"; do
  image_id=$(echo $image | awk -F ':' '{print $2}')
  image_repo=$(echo $image | awk -F ':' '{print $1}')
  case $DEPLOY_TYPE in
    'snapshot' )
      docker tag $image_id "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10003}"$ARCH:$GIT_SHA-$VERSION
      docker push "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10003}"$ARCH:$GIT_SHA-$VERSION
      ;;
    'staging' )
      docker tag $image_id "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10004}"$ARCH:latest
      docker push "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10004}"$ARCH:latest
      ;;
    'release' )
      docker tag $image_id "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10002}"$ARCH:latest
      docker push "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10002}"$ARCH:latest
      docker tag $image_id "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10002}"$ARCH:$VERSION
      docker push "${image_repo/edgexfoundry/nexus3.edgexfoundry.org:10002}"$ARCH:$VERSION
      export DOCKER_CONTENT_TRUST=1
      docker tag $image_id $image_repo$ARCH:$VERSION
      docker tag $image_id $image_repo$ARCH:latest
      docker push $image_repo$ARCH:$VERSION
      docker push $image_repo$ARCH:latest
      ;;
    * )
      echo "You must set DEPLOY_TYPE to one of (snapshot, staging, release)."
      exit 1
  esac
done

## Copy generated go binaries, copy to folder and tar up before pushing to nexus raw repos
## Note the the release case is on hold until the sigul work is completed as there is no way
## currently to do this in an automated fasion.
mkdir -p edgex-go-$VERSION
bin_dir=edgex-go-$VERSION/

go_bins=(cmd/export-client/export-client
         cmd/export-distro/export-distro
         cmd/core-metadata/core-metadata
         cmd/core-data/core-data
         cmd/core-command/core-command
         cmd/support-logging/support-logging)

for bin in "${go_bins[@]}"; do
  cp $bin $bin_dir
done

case $DEPLOY_TYPE in
  'snapshot')
    filename=edgex-go$ARCH-$GIT_SHA-$VERSION.tar.gz
    tar cvzf $filename $bin_dir
    curl -v -n --upload-file $filename https://nexus.edgexfoundry.org/content/sites/edgex-go/snapshots/$filename
    ;;
  'staging')
    filename=edgex-go$ARCH-$VERSION.tar.gz
    tar cvzf $filename $bin_dir
    curl -v -n --upload-file $filename https://nexus.edgexfoundry.org/content/sites/edgex-go/staging/$filename
    ;;
  'release')
    filename=edgex-go$ARCH-$VERSION.tar.gz
    tar cvzf $filename $bin_dir
    #curl -v -n --upload-file $filename https://nexus.edgexfoundry.org/content/sites/edgex-go-release/$filename
    ;;
  *)
    echo "You must set DEPLOY_TYPE to one of (snapshot, staging, release)."
    exit 1
    ;;
esac

#!/bin/bash

git show scripts:scripts/update_image.rb > update_image.rb

ruby update_image.rb . ./stash-repository
ret=$?

# 1 exit code means versions have changed
if [ "$ret" == "1" ]; then

    # Build docker image, use a test tag to not accidentially use the canonical version
    sudo docker build -t="atlassian/bitbucket-test" .
    # Sanity check, list images
    docker images

    # Test the running container
    git show scripts:scripts/test-bitbucket-status.sh > test-bitbucket-status.sh
    chmod u+x ./test-bitbucket-status.sh

    # Ensure permissions are correct
    sudo docker run -u root -v /data/stash:/var/atlassian/application-data/bitbucket atlassian/bitbucket-test chown -R daemon  /var/atlassian/application-data/bitbucket

    # Start Stash
    sudo docker run -v /data/stash:/var/atlassian/application-data/bitbucket --name="bitbucket" -d -p 7990:7990 -p 7999:7999 atlassian/bitbucket-test


    ./test-bitbucket-status.sh
    curl -v "http://localhost:7990/status"

    # Push changes
    git push --all git@bitbucket.org:atlassian/docker-atlassian-stash.git
else
    echo "No changes. Nothing to do"
fi





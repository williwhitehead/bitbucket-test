#!/bin/bash

git show scripts:scripts/update_image.rb > update_image.rb

ruby update_image.rb . ./stash-repository
ret=$?

# 1 exit code means versions have changed
if [ "$ret" == "1" ]; then
    
    # Build docker image, use a test tag to not accidentially use the canonical version
    sudo docker build -t="atlassian/stash-test" . 
    # Sanity check, list images
    docker images
    
    # Test the running container
    git show scripts:scripts/test-stash-status.sh > test-stash-status.sh
    chmod u+x ./test-stash-status.sh

    # Ensure permissions are correct
    sudo docker run -u root -v /data/stash:/var/atlassian/application-data/stash atlassian/stash-test chown -R daemon  /var/atlassian/application-data/stash

    # Start Stash
    sudo docker run -v /data/stash:/var/atlassian/application-data/stash --name="stash" -d -p 7990:7990 -p 7999:7999 atlassian/stash-test


    ./test-stash-status.sh
    curl -v "http://localhost:7990/status"

    # Push changes
    git push git@bitbucket.org:atlassian/docker-atlassian-stash.git HEAD:develop-test
else
    echo "No changes. Nothing to do"
fi





echo "== Checking if the 'aports' repository exists and is up to date =="; \
if [ -d ext/aports ]; then \
    echo "== Found ==" && \
    cd ext/aports && \
    export GIT_STATUS=$(git status -s -b HEAD); \
    echo ${GIT_STATUS} | \
         sed -e 's,^.*\origin\/,\"== Your local copy ,g' \
        -e 's,\[,is ,g' \
        -e 's,\], commits ==\",g'; \
    if [ $(echo ${GIT_STATUS} | grep "behind") ]; then \
        echo "== Updating ==" && \
        git pull; \
    else \
        echo "== Up to Date =="; \
    fi \
else \
    echo "== Not Found =="; \
    echo 'Cloning https://git.alpinelinux.org/aports into 'ext/aports'' && \
    git clone https://git.alpinelinux.org/aports ext/aports --single-branch --no-tags --depth=1; \
fi
HEROKUISH_DESCRIPTION = 'Herokuish uses Docker and Buildpacks to build applications like Heroku'
HEROKUISH_REPO_NAME ?= gliderlabs/herokuish
HEROKUISH_VERSION ?= 0.0.1
HEROKUISH_ARCHITECTURE = amd64
HEROKUISH_PACKAGE_NAME = herokuish_$(HEROKUISH_VERSION)_$(HEROKUISH_ARCHITECTURE).deb

DOKKU_DESCRIPTION = 'Docker powered mini-Heroku in around 100 lines of Bash'
DOKKU_REPO_NAME ?= progrium/dokku
DOKKU_ARCHITECTURE = amd64

PLUGINHOOK_DESCRIPTION = 'Simple dispatcher and protocol for shell-based plugins, an improvement to hook scripts'
PLUGINHOOK_REPO_NAME ?= progrium/pluginhook
PLUGINHOOK_VERSION ?= 0.2.0
PLUGINHOOK_ARCHITECTURE = amd64
PLUGINHOOK_PACKAGE_NAME = pluginhook_$(PLUGINHOOK_VERSION)_$(PLUGINHOOK_ARCHITECTURE).deb

SSHCOMMAND_DESCRIPTION = 'Turn SSH into a thin client specifically for your app'
SSHCOMMAND_REPO_NAME ?= progrium/sshcommand
SSHCOMMAND_VERSION ?= 0.0.1
SSHCOMMAND_ARCHITECTURE = amd64
SSHCOMMAND_PACKAGE_NAME = sshcommand_$(SSHCOMMAND_VERSION)_$(SSHCOMMAND_ARCHITECTURE).deb

GEM_ARCHITECTURE = amd64

GOROOT = /usr/lib/go
GOBIN = /usr/bin/go
GOPATH = /home/vagrant/gocode

.PHONY: install-from-deb deb-all deb-herokuish deb-dokku deb-gems deb-pluginhook deb-setup deb-sshcommand

install-from-deb:
	echo "--> Initial apt-get update"
	sudo apt-get update > /dev/null
	sudo apt-get install -y apt-transport-https curl

	echo "--> Installing docker gpg key"
	curl -sSL https://get.docker.com/gpg | apt-key add -

	echo "--> Installing dokku gpg key"
	curl --silent https://packagecloud.io/gpg.key 2> /dev/null | apt-key add - 2>&1 >/dev/null

	echo "--> Setting up apt repositories"
	echo "deb https://get.docker.io/ubuntu docker main" > /etc/apt/sources.list.d/docker.list
	echo "deb https://packagecloud.io/dokku/dokku/ubuntu/ trusty main" > /etc/apt/sources.list.d/dokku.list

	echo "--> Running apt-get update"
	sudo apt-get update > /dev/null

	echo "--> Installing pre-requisites"
	sudo apt-get install -y linux-image-extra-`uname -r`

	echo "--> Installing dokku"
	sudo apt-get install -y dokku

	echo "--> Done!"

deb-all: deb-herokuish deb-dokku deb-gems deb-pluginhook deb-sshcommand
	mv /tmp/*.deb .
	echo "Done"

deb-setup:
	echo "-> Updating deb repository and installing build requirements"
	sudo apt-get update > /dev/null
	sudo apt-get install -qq -y gcc git ruby1.9.1-dev 2>&1 > /dev/null
	command -v fpm > /dev/null || sudo gem install fpm --no-ri --no-rdoc
	ssh -o StrictHostKeyChecking=no git@github.com || true

deb-herokuish: deb-setup
	rm -rf /tmp/tmp /tmp/build $(HEROKUISH_PACKAGE_NAME)
	mkdir -p /tmp/tmp /tmp/build

	echo "-> Creating deb files"
	echo "#!/usr/bin/env bash" >> /tmp/tmp/post-install
	echo "sleep 5" >> /tmp/tmp/post-install
	echo "count=\`sudo docker images | grep gliderlabs/herokuish | wc -l\`" >> /tmp/tmp/post-install
	echo 'if [ "$$count" -ne 0 ]; then' >> /tmp/tmp/post-install
	echo "  echo 'Removing old herokuish image'" >> /tmp/tmp/post-install
	echo "  sudo docker rmi gliderlabs/herokuish" >> /tmp/tmp/post-install
	echo "fi" >> /tmp/tmp/post-install
	echo "echo 'Importing herokuish into docker (around 5 minutes)'" >> /tmp/tmp/post-install
	echo "sudo docker build -t gliderlabs/herokuish /var/lib/herokuish 1> /dev/null" >> /tmp/tmp/post-install

	echo "-> Cloning repository"
	git clone -q "git@github.com:$(HEROKUISH_REPO_NAME).git" /tmp/tmp/herokuish > /dev/null
	rm -rf /tmp/tmp/herokuish/.git /tmp/tmp/herokuish/.gitignore

	echo "-> Copying files into place"
	mkdir -p "/tmp/build/var/lib"
	cp -rf /tmp/tmp/herokuish /tmp/build/var/lib/herokuish

	echo "-> Creating $(HEROKUISH_PACKAGE_NAME)"
	sudo fpm -t deb -s dir -C /tmp/build -n herokuish -v $(HEROKUISH_VERSION) -a $(HEROKUISH_ARCHITECTURE) -p $(HEROKUISH_PACKAGE_NAME) --deb-pre-depends 'lxc-docker-1.6.2' --after-install /tmp/tmp/post-install --url "https://github.com/$(HEROKUISH_REPO_NAME)" --description $(HEROKUISH_DESCRIPTION) --license 'MIT License' .
	mv *.deb /tmp

deb-dokku: deb-setup
	rm -rf /tmp/tmp /tmp/build dokku_*_$(DOKKU_ARCHITECTURE).deb
	mkdir -p /tmp/tmp /tmp/build

	cp -r debian /tmp/build/DEBIAN
	mkdir -p /tmp/build/usr/local/bin
	mkdir -p /tmp/build/var/lib/dokku
	mkdir -p /tmp/build/usr/local/share/man/man1
	mkdir -p /tmp/build/usr/local/share/dokku/contrib

	cp dokku /tmp/build/usr/local/bin
	cp -r plugins /tmp/build/var/lib/dokku
	find plugins/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read plugin; do touch /tmp/build/var/lib/dokku/plugins/$$plugin/.core; done
	$(MAKE) help2man
	$(MAKE) addman
	cp /usr/local/share/man/man1/dokku.1 /tmp/build/usr/local/share/man/man1/dokku.1
	cp contrib/dokku-installer.rb /tmp/build/usr/local/share/dokku/contrib
	git describe --tags > /tmp/build/var/lib/dokku/VERSION
	cat /tmp/build/var/lib/dokku/VERSION | cut -d '-' -f 1 | cut -d 'v' -f 2 > /tmp/build/var/lib/dokku/STABLE_VERSION
	git rev-parse HEAD > /tmp/build/var/lib/dokku/GIT_REV
	sed -i "s/^Version: .*/Version: `cat /tmp/build/var/lib/dokku/STABLE_VERSION`/g" /tmp/build/DEBIAN/control
	dpkg-deb --build /tmp/build "/vagrant/dokku_`cat /tmp/build/var/lib/dokku/STABLE_VERSION`_$(DOKKU_ARCHITECTURE).deb"
	mv *.deb /tmp

deb-gems: deb-setup
	rm -rf /tmp/tmp /tmp/build rubygem-*.deb
	mkdir -p /tmp/tmp /tmp/build

	gem install --quiet --no-verbose --no-ri --no-rdoc --install-dir /tmp/tmp rack -v 1.5.2 > /dev/null
	gem install --quiet --no-verbose --no-ri --no-rdoc --install-dir /tmp/tmp rack-protection -v 1.5.3 > /dev/null
	gem install --quiet --no-verbose --no-ri --no-rdoc --install-dir /tmp/tmp sinatra -v 1.4.5 > /dev/null
	gem install --quiet --no-verbose --no-ri --no-rdoc --install-dir /tmp/tmp tilt -v 1.4.1 > /dev/null

	find /tmp/tmp/cache -name '*.gem' | xargs -rn1 fpm -d ruby -d ruby --prefix /var/lib/gems/1.9.1 -s gem -t deb -a $(GEM_ARCHITECTURE)
	mv *.deb /tmp

deb-pluginhook: deb-setup
	rm -rf /tmp/tmp /tmp/build $(PLUGINHOOK_PACKAGE_NAME)
	mkdir -p /tmp/tmp /tmp/build

	echo "-> Cloning repository"
	git clone -q "git@github.com:$(PLUGINHOOK_REPO_NAME).git" /tmp/tmp/pluginhook > /dev/null
	rm -rf /tmp/tmp/pluginhook/.git /tmp/tmp/pluginhook/.gitignore

	echo "-> Copying files into place"
	mkdir -p /tmp/build/usr/local/bin $(GOPATH)
	sudo apt-get update > /dev/null
	sudo apt-get install -qq -y git golang mercurial 2>&1 > /dev/null
	export PATH=$(PATH):$(GOROOT)/bin:$(GOPATH)/bin && export GOROOT=$(GOROOT) && export GOPATH=$(GOPATH) && go get "golang.org/x/crypto/ssh/terminal"
	export PATH=$(PATH):$(GOROOT)/bin:$(GOPATH)/bin && export GOROOT=$(GOROOT) && export GOPATH=$(GOPATH) && cd /tmp/tmp/pluginhook && go build -o pluginhook
	mv /tmp/tmp/pluginhook/pluginhook /tmp/build/usr/local/bin/pluginhook

	echo "-> Creating $(PLUGINHOOK_PACKAGE_NAME)"
	sudo fpm -t deb -s dir -C /tmp/build -n pluginhook -v $(PLUGINHOOK_VERSION) -a $(PLUGINHOOK_ARCHITECTURE) -p $(PLUGINHOOK_PACKAGE_NAME) --url "https://github.com/$(PLUGINHOOK_REPO_NAME)" --description $(PLUGINHOOK_DESCRIPTION) --license 'MIT License' .
	mv *.deb /tmp

deb-sshcommand: deb-setup
	rm -rf /tmp/tmp /tmp/build $(SSHCOMMAND_PACKAGE_NAME)
	mkdir -p /tmp/tmp /tmp/build

	echo "-> Cloning repository"
	git clone -q "git@github.com:$(SSHCOMMAND_REPO_NAME).git" /tmp/tmp/sshcommand > /dev/null
	rm -rf /tmp/tmp/sshcommand/.git /tmp/tmp/sshcommand/.gitignore

	echo "-> Copying files into place"
	mkdir -p "/tmp/build/usr/local/bin"
	cp /tmp/tmp/sshcommand/sshcommand /tmp/build/usr/local/bin/sshcommand
	chmod +x /tmp/build/usr/local/bin/sshcommand

	echo "-> Creating $(SSHCOMMAND_PACKAGE_NAME)"
	sudo fpm -t deb -s dir -C /tmp/build -n sshcommand -v $(SSHCOMMAND_VERSION) -a $(SSHCOMMAND_ARCHITECTURE) -p $(SSHCOMMAND_PACKAGE_NAME) --url "https://github.com/$(SSHCOMMAND_REPO_NAME)" --description $(SSHCOMMAND_DESCRIPTION) --license 'MIT License' .
	mv *.deb /tmp

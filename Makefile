# The following variables need to be set via Gitlab's CI/CD Variables
#
# - CI_GIT_BOT
# - CI_GIT_TOKEN
# - DOCKER_TAG

TLANG ?= deu

PDFS = $(shell find . -name \*.pdf)
TXTS = $(subst .pdf,.txt,$(PDFS))

REPO_URL = $(word 2,$(subst @, ,$(CI_REPOSITORY_URL)))

CI_COMMIT_REF_NAME ?= master

HOSTNAME = $(shell hostname)

# --- default target ---
.PHONY: doit
doit:
	git add .
	make rename
	git pull
	make -j 6 textfiles
	git add .
	./okdoc/sort.rb -ai

.PHONY: install
install:
	([ ! -f config.yml ] && cp okdoc/config.yml .; true)
	([ ! -f .gitlab-ci.yml ] && cp okdoc/.gitlab-ci.yml .; true)
	cp okdoc/.gitattributes .
	cd okdoc; bundle install; cd -
	git init
	git config merge.keepMine.name "always keep mine during merge"
	git config merge.keepMine.driver "true"

.PHONY: all
all: rename textfiles # sort

.PHONY: build
build: Dockerfile
	docker build -t okocr .

.PHONY: textfiles-docker
textfiles-docker: build
	docker run --rm \
	  -it \
	  --name devtest \
	  --mount type=bind,source="$$(pwd)",target=/app \
	  okocr:latest /bin/sh -c "cd /app && make textfiles"
	# The files created through docker will have the user root which
	# will make them inaccessible to the local user
	sudo chown -R $$USER: .

.PHONY: rename
rename:
	./okdoc/rename.rb | /bin/sh

.PHONY: textfiles
textfiles: $(TXTS)

# --- this is what's called from ci
.PHONY: ci
ci: rename
	make textfiles
	./okdoc/sort.rb -ay

%.txt: %.pdf $(OCRMYPDF) $(PDFTOTEXT)
	# Only run ocrmypdf if the .txt file doesn't exist; independent if the timestamp is newer
	# But first, ensure that there's no false positive on 'PDF is encrypted'
	([ ! -f $@ ] && $(QPDF) --decrypt --replace-input $<; true)
	([ ! -f $@ ] && $(OCRMYPDF) -r -s --rotate-pages-threshold 13 -l $(TLANG) $< $< && $(PDFTOTEXT) $< $@; true)

.PHONY: sort
sort:
	./okdoc/sort.rb

# ------------------------------ register

.PHONY: push
push: $(GIT)
	# add files
	$(GIT) add .
	# re-write the log
	echo "From $(HOSTNAME) at $(shell date -I)" > log.txt
	$(GIT) status >> log.txt
	$(GIT) log --name-status --oneline >> log.txt
	$(GIT) add log.txt
	# commit and push everything
	$(GIT) commit -m "automatic commit via make from $(HOSTNAME)"
	$(GIT) pull --no-edit origin ${CI_COMMIT_REF_NAME}
	$(GIT) push || $(GIT) push "https://${CI_GIT_BOT}:$(CI_GIT_TOKEN)@$(REPO_URL)" "HEAD:$(CI_COMMIT_REF_NAME)"; true

# this target is called by the upload handler of pure-ftpd
.PHONY: register
register: push
	aplay ./okdoc/register.wav

# ------------------------------ dependencies

GIT = /usr/bin/git
OCRMYPDF = /usr/bin/ocrmypdf
QPDF = /usr/bin/qpdf
PDFTOTEXT = /usr/bin/pdftotext

$(GIT):
	sudo apt-get install -y git

$(OCRMYPDF):
	sudo apt-get install -y ocrmypdf tesseract-ocr-deu

$(PDFTOTEXT):
	sudo apt-get install -y poppler-utils

# ------------------------------ ci-runner

.PHONY: build-ci
build-ci:
	cd okdoc; docker build -t $(DOCKER_TAG) .
	cd okdoc; docker push $(DOCKER_TAG)

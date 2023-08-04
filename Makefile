.PHONY: compile

build:
	@mkdir -p release
	mix escript.build
	mv -f pidge release/pidge

bookmarklet_compile:
	@mkdir -p release
	@uglifyjs project-roe-bookmarklet.js -m -c -o release/project-roe-bookmarklet.min.js
	@echo "javascript:"`node -e "console.log(encodeURIComponent(require('fs').readFileSync('release/project-roe-bookmarklet.min.js', 'utf8')))"` > release/bookmarklet.txt
	cat release/bookmarklet.txt | pbcopy
	@echo "Copied bookmarklet to clipboard"

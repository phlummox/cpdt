MODULES_NODOC := Tactics
MODULES_DOC   := Intro StackMachine
MODULES       := $(MODULES_NODOC) $(MODULES_DOC)
VS            := $(MODULES:%=src/%.v)
VS_DOC        := $(MODULES_DOC:%=%.v)
GLOBALS       := .coq_globals

.PHONY: coq clean doc dvi html

coq: Makefile.coq
	make -f Makefile.coq

Makefile.coq: Makefile $(VS)
	coq_makefile $(VS) \
		COQC = "coqc -I src -impredicative-set \
			-dump-glob $(GLOBALS)" \
		-o Makefile.coq

clean:: Makefile.coq
	make -f Makefile.coq clean
	rm -f Makefile.coq .depend $(GLOBALS) \
		latex/*.sty latex/cpdt.*

doc: latex/cpdt.dvi latex/cpdt.pdf html

latex/cpdt.tex: Makefile $(VS)
	cd src ; coqdoc --latex $(VS_DOC) \
		-p "\usepackage{url}" \
		-p "\title{Certified Programming with Dependent Types}" \
		-p "\author{Adam Chlipala}" \
		-p "\iffalse" \
		-o ../latex/cpdt.tex

latex/cpdt.dvi: latex/cpdt.tex
	cd latex ; latex cpdt ; latex cpdt

latex/cpdt.pdf: latex/cpdt.dvi
	cd latex ; pdflatex cpdt

html: Makefile $(VS)
	cd src ; coqdoc $(VS_DOC) -toc \
		--glob-from ../$(GLOBALS) \
		-d ../html

dvi:
	xdvi latex/cpdt

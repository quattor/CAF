BEGIN {
    our $TQU = <<'EOF';
[load]
prefix=CAF::
modules=Application,FileEditor,FileReader,FileWriter,History,Kerberos,Lock,Log,Object,ObjectText,Path,Process,ReporterMany,Reporter,RuleBasedEditor,Service,TextRender
[doc]
# no pan code in CAF
panpaths=NOPAN
EOF
}
use Test::Quattor::Unittest;

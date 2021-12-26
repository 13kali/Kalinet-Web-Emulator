#!/bin/sh -e
if [ ! -f kalinetos/README ]; then
	git submodule init
	git submodule update
fi
cd kalinetos
if [ ! -f tools/blkpack ]; then
	git stash push --all
	cd tools
	make blkpack
	cd ../cvm
	make blkfs stage
	cd ..
fi
cd ..
rm -rf build
mkdir -p build
cd pdf
./build.pl >../build/kalinetos.fodt
cd ..
perl -n - emul0-xcomp.fs >build/emul0-bootstrap.fs <<'EOF'
sub printblock {
	my $num = $_[0];
	my $fs = "kalinetos/blk.fs";
	if ($num =~ /^3/) {
		$num =~ s/^3/0/;
		$fs = "kalinetos/cvm/cvm.fs";
	}
	open(my $in, "<", $fs) or die $!;
	my $write=0;
	while(my $line = <$in>) {
		chomp $line;
		if ($line =~ /^\( ----- $num \)$/) {
			$write = 1;
			next;
		} elsif ($write and $line =~ /^\( ----- [0-9]+ \)$/) {
			$write = 2;
			last;
		}
		print $line.$/ if $write;
	}
	if ($write ne 2) {
		die "Block $num not found!\n";
	}
	close($in);
}
if (/#=/) {
	foreach $i (/#=([0-9]+)/g) {
		print "( #=".$i." )".$/;
		printblock $i;
	}
} else {
	print;
}
EOF
sed -i "s/^'?/( ((( ) '?/g;s/CELLS! NOT \[IF\]/CELLS! NOT \[IF\]( ))) )/g;s/THEN\]$/THEN\] ( ))) )/g;s/THEN DROP ; \[THEN\]/THEN DROP ; ( ((( ) \[THEN\]/g;s/^\\\\ # //g" build/emul0-bootstrap.fs
echo 'ORG 256 /MOD 2 PC! 2 PC! HERE 256 /MOD 2 PC! 2 PC!' >>build/emul0-bootstrap.fs
cat kalinetos/arch/z80/blk.fs kalinetos/arch/avr/blk.fs kalinetos/arch/8086/blk.fs \
        kalinetos/arch/6809/blk.fs kalinetos/arch/6502/blk.fs >build/combined.fs
patch -d build <blkfs.patch
cat kalinetos/blk.fs build/combined.fs | kalinetos/tools/blkpack > build/blkfs.bfs
OVERLAY=kalinetos/cvm/blkfs # for 0 only
for i in 0 1 2 3 4 ; do
	echo Building emul$i.rom
	kalinetos/cvm/stage $OVERLAY <emul$i-xcomp.fs >build/emul$i.rom
	OVERLAY=build/blkfs.bfs # for 1 2 3 4
done
echo "Done!"

#!/usr/bin/env perl
# Parse a list of refseq and check CDS coverage

use warnings;
use Getopt::Std;
use strict;

our ($opt_h, $opt_H, $opt_b, $opt_D, $opt_d, $opt_s, $opt_c, $opt_S, $opt_E, $opt_n, $opt_N, $opt_e, $opt_g, $opt_x, $opt_f, $opt_r, $opt_B, $opt_z, $opt_v, $opt_p, $opt_F, $opt_C, $opt_m, $opt_Q, $opt_T, $opt_L, $opt_q, $opt_Z, $opt_X, $opt_P, $opt_3, $opt_k, $opt_R, $opt_G, $opt_a, $opt_o, $opt_O, $opt_V);
unless( getopts( 'hHvzpDCFL3d:b:s:e:S:E:n:c:g:x:f:r:B:N:Q:m:T:q:Z:X:P:k:R:G:a:o:O:V:' )) {
    USAGE();
}
USAGE() if ( $opt_H );
USAGE() unless ( $opt_b );
my $BAM = $opt_b; # the bam file
my $sample = $1 if ( $BAM =~ /([^\/\._]+?).sorted[^\/]*.bam/ );
if ( $opt_n ) {
    $sample = $1 if ( $BAM =~ /$opt_n/ );
}
$sample = $opt_N if ( $opt_N );
unless($sample) { $sample = $1 if ( $BAM =~ /([^\/]+?)[_\.][^\/]*bam/ ); }

$opt_d = "\t" unless( $opt_d );
my $c_col = $opt_c ? $opt_c - 1 : 2;
my $S_col = $opt_S ? $opt_S - 1 : 6;
my $E_col = $opt_E ? $opt_E - 1 : 7;
my $s_col = $opt_s ? $opt_s - 1 : 9;
my $e_col = $opt_e ? $opt_e - 1 : 10;
my $g_col = $opt_g ? $opt_g - 1 : 12;

$s_col = $S_col if ( $opt_S && (!$opt_s) );
$e_col = $E_col if ( $opt_E && (!$opt_e) );

if ( $opt_L ) {
    $opt_p = 1;
    $c_col = 1 - 1;
    $S_col = 2 - 1;
    $E_col = 2 - 1;
    $s_col = 2 - 1;
    $e_col = 2 - 1;
    $g_col = 3 - 1;
    $opt_d = ":";
}

my $VEXT = defined($opt_X) ? $opt_X : 1; # the extension of deletion and insertion for complex variants
$opt_P = defined($opt_P) ? $opt_P : 5;
$opt_k = $opt_k ? $opt_k : 0; # The extension for indels for realignments
my $fasta = $opt_G ? $opt_G : "/ngs/reference_data/genomes/Hsapiens/hg19/seq/hg19.fa";
my %CHRS; # Key: chr Value: chr_len
my $EXT = defined($opt_x) ? $opt_x : 0;
my $FREQ = $opt_f ? $opt_f : 0.05;
my $QRATIO = $opt_o ? $opt_o : 1.5; # The Qratio
my $BIAS = 0.05; # The cutoff to decide whether a positin has read strand bias
my $MINB = $opt_B ? $opt_B : 2; # The minimum reads for bias calculation
my $MINR = $opt_r ? $opt_r : 2; # The minimum reads for variance allele
my $GOODQ = defined($opt_q) ? $opt_q : 23; # The phred score in fastq to be considered as good base call
$opt_O = defined($opt_O) ? $opt_O : 0; # The minimun mean mapping quality to be considered
$opt_V = defined($opt_V) ? $opt_V : 0.03; # The minimun alelle frequency allowed in normal for a somatic mutation
if ( $opt_p ) {
    $FREQ = -1;
    $MINR = 0;
}
if ( $opt_h ) {
    print join("\t", qw(Sample Gene Chr Start End Ref Alt Depth AltDepth RefFwdReads RefRevReads AltFwdReads AltRevReads Genotype AF Bias PMean PStd QMean QStd 5pFlankSeq 3pFlankSeq)), "\n";
}
my @SEGS = ();
if ( $opt_R ) {
    my ($chr, $reg, $gene) = split(/:/, $opt_R);
    #$chr = "chr$chr" unless( $chr =~ /^chr/ );
    $gene = $chr unless( $gene );
    my ($start, $end) = split(/-/, $reg);
    $end = $start unless( $end );
    $start =~ s/,//g;
    $end =~ s/,//g;
    $start -= $EXT;
    $end += $EXT;
    push(@SEGS, [[$chr, $start, $end, $gene]]);
} else {
    while( <> ) {
	chomp;
	next if ( /^#/ );
	next if ( /^browser/i );
	next if ( /^track/i );
	my @A = split(/$opt_d/);
	my ($chr, $cdss, $cdse, $gene) = @A[$c_col, $S_col, $E_col, $g_col];
	my @starts = split(/,/, $A[$s_col]);
	my @ends = split(/,/, $A[$e_col]);
	my @CDS = ();
	#$chr = "chr$chr" unless ($chr =~ /^chr/ );
	$gene = $chr unless( $gene );
	for(my $i = 0; $i < @starts; $i++) {
	    my ($s, $e) = ($starts[$i], $ends[$i]);
	    next if ( $cdss > $e ); # not a coding exon
	    last if ( $cdse < $s ); # No more coding exon
	    $s = $cdss if ( $s < $cdss );
	    $e = $cdse if ( $e > $cdse );
	    $s -= $EXT; # unless ( $s == $cdss );
	    $e += $EXT; # unless ( $e == $cdse );
	    $s++ if ( $opt_z );
	    push(@CDS, [$chr, $s, $e, $gene]);
	}
	push(@SEGS, \@CDS);
    }
}

for(my $i = 0; $i < @SEGS; $i++) {
    for(my $j = 0; $j < @{ $SEGS[$i] }; $j++) {
	my ($bam1, $bam2) = split(/\|/, $BAM);
	my @bams = split(/:/, $bam1);
	open(BAMH, "samtools view -H $bams[0] |");
	while(<BAMH>) {
	    if ( /\@SQ\s+SN:(\S+)\s+LN:(\d+)/ ) {
	        $CHRS{ $1 } = $2;
	    }
	}
	close(BAMH);
	$fasta = $CHRS{ 1 } ? "/ngs/reference_data/genomes/Hsapiens/GRCh37/seq/GRCh37.fa" : "/ngs/reference_data/genomes/Hsapiens/hg19/seq/hg19.fa" unless( $opt_G );
	if ( $bam2 ) { # pair mode
	    somdict($SEGS[$i]->[$j], toVars(@{ $SEGS[$i]->[$j] }, $bam1), toVars(@{ $SEGS[$i]->[$j] }, $bam2));
	} else {
	    vardict($SEGS[$i]->[$j], toVars(@{ $SEGS[$i]->[$j] }, $bam1));
	}
    }
}

sub varType {
    my ($ref, $var) = @_;
    if ( length($ref) == 1 && length($var) == 1 ) {
        return "SNV";
    } elsif ( length($ref) == 1 && length($var) > 1 ) {
        return "Insertion";
    } elsif (length($ref) > 1 && length($var) == 1 ) {
        return "Deletion";
    }
    return "Complex";
}

sub vardict {
    my ($seg, $vars) = @_;
    my ($chr, $S, $E, $G) = @{ $seg };
    for(my $p = $S; $p <= $E; $p++) {
	my $vref;
	unless( $vars->{ $p }->{ VAR } ) {
	    next unless( $opt_p );
	    $vref = $vars->{ $p }->{ REF };
	} elsif ($vars->{ $p }->{ VAR }) {
	    unless( isGoodVar( $vars->{ $p }->{ VAR }->[0] ) ) {
	        next unless( $opt_p );
	    }
	    $vref = $vars->{ $p }->{ VAR }->[0];
	} else {
	    print join("\t", $sample, $G, $chr, $p, $p, "", "", 0, 0, 0, 0, 0, 0, "", 0, "0;0", 0, 0, 0, 0, 0, "", 0, 0, 0, 0, "", ""), "\n";
	    next;
	}
	print join("\t", $sample, $G, $chr, $vref->{sp}, $vref->{ep}, $vref->{refallele}, $vref->{varallele}, $vref->{tcov}, $vref->{ cov }, $vref->{rfc}, $vref->{rrc}, $vref->{ fwd }, $vref->{ rev }, $vref->{ genotype }, $vref->{ freq }, $vref->{ bias }, $vref->{ pmean }, $vref->{ pstd }, $vref->{ qual }, $vref->{qstd}, $vref->{mapq}, $vref->{qratio}, $vref->{hifreq}, $vref->{extrafreq}, $vref->{shift3}, $vref->{msi}, $vref->{ leftseq }, $vref->{ rightseq }, "$chr:$S-$E");
	print "\t", $vref->{ DEBUG } if ( $opt_D );
	print "\n";
    }
    
}

sub somdict {
    my ($seg, $vars1, $vars2) = @_;
    my ($chr, $S, $E, $G) = @{ $seg };
    my @hdrs = qw(tcov cov rfc rrc fwd rev genotype freq bias pmean pstd qual qstd mapq qratio hifreq extrafreq);
    my $FISHERP = 0.01;
    for(my $p = $S; $p <= $E; $p++) {
	 next unless($vars1->{$p} || $vars2->{$p}); # both samples have no coverage
	 if( ! $vars1->{ $p } ) { # no coverage for sample 1
	     next unless( $vars2->{$p}->{ VAR } && isGoodVar($vars2->{$p}->{ VAR }->[0]) );
	     print join("\t", $sample, $G, $chr, (map{ $vars2->{$p}->{ VAR }->[0]->{ $_ }; } ("sp", "ep", "refallele", "varallele")), (map{ 0; } @hdrs), (map { $vars2->{$p}->{ VAR }->[0]->{ $_ }; } (@hdrs, "shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", "Deletion", varType($vars2->{$p}->{ VAR }->[0]->{ refallele }, $vars2->{$p}->{ VAR }->[0]->{ varallele })), "\n";
	 } elsif( ! $vars2->{ $p } ) { # no coverage for sample 2
	     next unless( $vars1->{$p}->{ VAR } && isGoodVar($vars1->{$p}->{ VAR }->[0]) );
	     print join("\t", $sample, $G, $chr, (map { $vars1->{$p}->{ VAR }->[0]->{ $_ }; } ("sp", "ep", "refallele", "varallele", @hdrs)), (map { 0; } @hdrs), (map { $vars1->{$p}->{ VAR }->[0]->{$_};} ("shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", "SampleSpecific", varType($vars1->{$p}->{ VAR }->[0]->{ refallele }, $vars1->{$p}->{ VAR }->[0]->{ varallele })), "\n";
	 } else { # both samples have coverage
	     my ($v1, $v2) = ($vars1->{$p}, $vars2->{$p});
	     next unless ( $v1->{ VAR } || $v2->{ VAR } );
	     if ( $v1->{ VAR } ) {
	         if( isGoodVar($v1->{ VAR }->[0]) ) {
		     my $nt = $v1->{ VAR }->[0]->{ n };
		     if ( length($nt) > 1 && length($v1->{ VAR }->[0]->{ refallele }) == length($v1->{ VAR }->[0]->{ varallele }) ) {
			 my $fnt = substr($nt, 0, -1); $fnt =~ s/&$//;
			 my $lnt = substr($nt, 1); $lnt =~ s/^&//; substr($lnt, 1, 0) = "&" if ( length($lnt) > 1 );
			 if ( $v2->{ VARN }->{ $fnt } && isGoodVar($v2->{ VARN }->{ $fnt })) {
			     $v1->{ VAR }->[0]->{ sp } += length($v1->{ VAR }->[0]->{ refallele }) - 1;
			     $v1->{ VAR }->[0]->{ ep } += length($v1->{ VAR }->[0]->{ refallele }) - 1;
			     $v1->{ VAR }->[0]->{ refallele } = substr($v1->{ VAR }->[0]->{ refallele }, -1 );
			     $v1->{ VAR }->[0]->{ varallele } = substr($v1->{ VAR }->[0]->{ varallele }, -1 );
			 } elsif ( $vars2->{ $p + length($nt) -2 }->{ VARN }->{ $lnt } && isGoodVar($vars2->{ $p + length($nt) -2 }->{ VARN }->{ $lnt })) {
			     $v1->{ VAR }->[0]->{ refallele } = substr($v1->{ VAR }->[0]->{ refallele }, 0, -1 );
			     $v1->{ VAR }->[0]->{ varallele } = substr($v1->{ VAR }->[0]->{ varallele }, 0, -1 );
			 }
		     }
		     if ( $v2->{ VARN }->{ $nt } ) {
			 my $type = isGoodVar( $v2->{ VARN }->{ $nt } ) ? "Germline" : ($v2->{ VARN }->{ $nt }->{ freq } < $opt_V || $v2->{ VARN }->{ $nt }->{ cov } <= 1 ? "LikelySomatic" : "AFDiff");
			 #$type = "StrongSomatic" if ( isNoise($v2->{ VARN }->{ $nt }) );
			 print join("\t", $sample, $G, $chr, (map { $v1->{ VAR }->[0]->{ $_ }; } ("sp", "ep", "refallele", "varallele", @hdrs)), (map { $v2->{ VARN }->{ $nt }->{ $_ }; } (@hdrs, "shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", $type, varType($v1->{ VAR }->[0]->{ refallele }, $v1->{ VAR }->[0]->{ varallele })), "\n";
		     } else { # sample 1 only, potential somatic
			 my @tvf = $v2->{ REF } ? (map { $v2->{ REF }->{ $_ }; } @hdrs) : ($v2->{ VAR }->[0]->{ tcov } ? $v2->{ VAR }->[0]->{ tcov } : 0, map { 0; } (1..16));
			 print join("\t", $sample, $G, $chr, (map { $v1->{ VAR }->[0]->{ $_ }; } ("sp", "ep", "refallele", "varallele", @hdrs)), @tvf, (map { $v1->{ VAR }->[0]->{$_};} ("shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", "StrongSomatic", varType($v1->{ VAR }->[0]->{ refallele }, $v1->{ VAR }->[0]->{ varallele })), "\n";
		     }
		 } else {
		     next unless( $v2->{ VAR } );
		     next unless( isGoodVar( $v2->{ VAR }->[0] ) );
		     # potentail LOH
		     my $nt = $v2->{ VAR }->[0]->{ n };
		     if ( $v1->{ VARN }->{ $nt } ) {
			 my $type = $v1->{ VARN }->{ $nt }->{ freq } < $opt_V ? "LikelyLOH" : "Germlin";
			 print join("\t", $sample, $G, $chr, (map { $v1->{ VARN }->{ $nt }->{ $_ }; } ("sp", "ep", "refallele", "varallele", @hdrs)), (map { $v2->{ VAR }->[0]->{ $_ }; } (@hdrs, "shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", $type, varType($v1->{ VARN }->{ $nt }->{ refallele }, $v1->{ VARN }->{ $nt }->{ varallele })), "\n";
		     } else {
			 my @th1 = $v1->{ REF } ? (map { $v1->{ REF }->{ $_ } } @hdrs) : ($v1->{ VAR }->[0]->{ tcov }, (map { 0; } @hdrs[1..$#hdrs]));
			 print join("\t", $sample, $G, $chr, (map { $v2->{ VAR }->[0]->{ $_ }; } ("sp", "ep", "refallele", "varallele")), @th1, (map { $v2->{ VAR }->[0]->{ $_ }; } (@hdrs, "shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", "StrongLOH", varType($v2->{ VAR }->[0]->{ refallele }, $v2->{ VAR }->[0]->{ varallele })), "\n";
		     }
		 }
	     } elsif ( $v2->{ VAR } ) { # sample 1 has only reference
	         next unless( isGoodVar( $v2->{ VAR }->[0] ) );
		 # potential LOH
		 my @th1 = map { $v1->{ REF }->{ $_ } } @hdrs;
		 print join("\t", $sample, $G, $chr, (map { $v2->{ VAR }->[0]->{ $_ }; } ("sp", "ep", "refallele", "varallele")), @th1, (map { $v2->{ VAR }->[0]->{ $_ }; } (@hdrs, "shift3", "msi", "leftseq", "rightseq")), "$chr:$S-$E", "StrongLOH", varType($v2->{ VAR }->[0]->{ refallele }, $v2->{ VAR }->[0]->{ varallele })), "\n";
	     }
	 }
    }
}

# A variance is considered noise if the quality is below $GOODQ and there're no more than 3 reads
sub isNoise {
    my $vref = shift;
    if ( $vref->{ qual } < 12 && $vref->{ cov } <= 3 ) {
        $vref->{ tcov } -= $vref->{ cov };
        $vref->{ cov } = 0;
        $vref->{ fwd } = 0;
        $vref->{ rev } = 0;
        $vref->{ freq } = 0;
	return 1;
    }
    return 0;
}
# Determine whether a variant meet specified criteria
sub isGoodVar {
    my $vref = shift;
    return 0 if ( $vref->{ freq } < $FREQ );
    return 0 if ( $vref->{ cov } < $MINR );
    return 0 if ( $vref->{ pmean } < $opt_P );
    return 1 if ( $vref->{ freq } > 0.6 );
    return 0 if ( $vref->{ qual } < $GOODQ );
    return 0 if ( $vref->{ qratio } < $QRATIO );
    return 0 if ( $vref->{ mapq } < $opt_O );
    return 0 if ( $vref->{ msi } > 10 && $vref->{ freq } < 0.5 );
    return 0 if ( $vref->{ bias } eq "2;1" && $vref->{ freq } < 0.25 );
    return 1;
}

sub addCnt {
    my ($vref, $dir, $rp, $q, $Q) = @_;  # ref dir read_position quality
    $vref->{ cnt }++;
    $vref->{ $dir }++;
    $vref->{ pmean } += $rp;
    $vref->{ qmean } += $q;
    $vref->{ Qmean } += $Q;
    $q >= $GOODQ ? $vref->{ hicnt }++ : $vref->{ locnt }++;
}

# Construct a variant structure given a segment and BAM files.
sub toVars {
    my ($chr, $START, $END, $gene, $bam) = @_;
    my %REF;
    my %cov;
    my %var;
    my %hash;
    my %dels5;
    my %ins;
    my %sclip3; # soft clipped at 3'
    my %sclip5; # soft clipped at 5'
    my @bams = split(/:/, $bam);
    foreach my $bami (@bams) {
	my $tsamcnt = `samtools view $bami $chr:$START-$END | head -1`;
	next unless( $tsamcnt || $opt_p ); # to avoid too much IO for exome and targeted while the BED is whole genome
	# Get the reference sequence
	my $s_start = $START - $EXT - 500 < 1 ? 1 : $START - $EXT - 500;
	my $s_end = $END + $EXT + 500 > $CHRS{ $chr } ? $CHRS{ $chr } : $END + $EXT + 500;
	my ($header, $exon) = split(/\n/, `samtools faidx $fasta $chr:$s_start-$s_end`, 2);
	$exon =~ s/\s+//g;
	for(my $i = $s_start; $i <= $s_start + length($exon); $i++) {
	    $REF{ $i } = uc(substr( $exon, $i - ($s_start), 1 ));
	}
	$chr =~ s/^chr// if ( $opt_C );
	open(SAM, "samtools view $bami $chr:$START-$END |");
	while( <SAM> ) {
	    if ( $opt_Z ) {
	        next if ( rand() <= $opt_Z );
	    }
	    my @a = split(/\t/);
	    #while( $a[5] =~ /(\d+)[DI]/g ) {
	    #    $a[4] += $1 - 1;  # Adjust mapping quality for indel alignments
	    #}
	    next if ( defined($opt_Q) && $a[4] < $opt_Q ); # ignore low mapping quality reads
	    #next if ( $opt_F && ($a[1] & 0x200 || $a[1] & 0x100) ); # ignore "non-primary alignment", or quality failed reads.
	    next if ( $opt_F && ($a[1] & 0x100) ); # ignore "non-primary alignment"
	    if ( $opt_m ) {
		my @segid = $a[5] =~ /(\d+)[ID]/g; # For total indels
		my $idlen = 0; $idlen += $_ foreach(@segid);
	        if ( /NM:i:(\d+)/ ) {  # number of mismatches.  Don't use NM since it includes gaps, which can be from indels
		    next if ( ($1-$idlen) > $opt_m ); # edit distance - indels is the # of mismatches
		} else {
		    print STDERR "No XM tag for mismatches. $_\n" if ( $opt_D );
		    next;
		}
	    }
	    my $start = $a[3];
	    my $n = 0; # keep track the read position, including softclipped
	    my $p = 0; # keep track the position in the alignment, excluding softclipped
	    my $dir = $a[1] & 0x10 ? "-" : "+";
	    my @segs = $a[5] =~ /(\d+)[MI]/g; # Only match and insertion counts toward read length
	    my @segs2 = $a[5] =~ /(\d+)[MIS]/g; # For total length, including soft-clipped bases
	    my $rlen = 0; $rlen += $_ foreach(@segs); #$stat->sum(\@segs); # The read length for matched bases
	    my $rlen2= 0; $rlen2 += $_ foreach(@segs2); #$stat->sum(\@segs2); # The total length, including soft-clipped bases

	    # Amplicon based calling
	    if ( $opt_a ) {
		my ($dis, $ovlp) = split( /:/, $opt_a );
		($dis, $ovlp) = (5, 0.95) unless($dis && $ovlp);
		my @segs3 = $a[5] =~ /(\d+)[MID]/g; # For total alignment length, including soft-clipped bases and gaps
		my $rlen3= 0; $rlen3 += $_ foreach(@segs3); # The total aligned length, including soft-clipped bases and gaps
		my ($segstart, $segend) = ($a[3], $a[3]+$rlen3);
		if ($a[8]) {
		    ($segstart, $segend) = $a[8] > 0 ? ($segstart, $segstart+$a[8]) : ($a[7], $segend);
		}
		# No segment overlapping test since samtools should take care of it
		my $ts1 = $segstart > $START ? $segstart : $START;
		my $te1 = $segend < $END ? $segend : $END;
		next unless( (abs($segstart - $START) <= $dis || abs($segend - $END) <= $dis ) && abs(($ts1-$te1)/($segend-$segstart)) > $ovlp);
	    }
	    my $offset = 0;
	    if ($a[5] =~ /^(\d+)S(\d+)[ID]/) {
	        my $tslen = $1 + $2;
		$tslen .= "S";
		$a[5] =~ s/^\d+S\d+[ID]/$tslen/;
	    }
	    if ($a[5] =~ /(\d+)[ID](\d+)S$/) {
	        my $tslen = $1 + $2;
		$tslen .= "S";
		$a[5] =~ s/^\d+[ID]\d+S$/$tslen/;
	    }
	    my @cigar = $a[5] =~ /(\d+)([A-Z])/g;

	    for(my $ci = 0; $ci < @cigar; $ci += 2) {
		my $m = $cigar[$ci];
		my $C = $cigar[$ci+1];
		$C = "S" if ( ($ci == 0 || $ci == @cigar - 2) && $C eq "I" ); # Treat insertions at the edge as softclipping
		if ( $C eq "N" ) {
		    $start += $m;
		    $offset = 0;
		    next;
		} elsif ( $C eq "S" ) {
		    if ( $ci == 0 ) { # 5' soft clipped
			# align softclipped but matched sequences due to mis-softclipping
			while( $m-1 >= 0 && $start - 1 > 0 && $start - 1 <= $CHRS{ $chr } && $REF{ $start-1 } eq substr($a[9], $m-1, 1) && ord(substr($a[10],$m-1, 1))-33 > 10) {
			    $hash{ $start - 1 }->{ $REF{ $start - 1 } }->{ cnt } = 0 unless( $hash{ $start - 1 }->{ $REF{ $start - 1 } }->{ cnt } );
			    addCnt($hash{ $start - 1 }->{ $REF{ $start - 1 } }, $dir, $m, ord(substr($a[10],$m-1, 1))-33, $a[4]);
			    $cov{ $start - 1 }++;
			    $start--; $m--;
			}
			if ( $m > 0 ) {
			    my $q = ord(substr($a[10], $m-1, 1))-33;
			    #unless (islowqual(substr($a[10], 0, $m))) {
			    my $qn = 0;
			    for(my $si = $m-1; $si >= 0; $si--) {
				 last if (ord(substr($a[10], $si, 1))-33 < 7);
				 $qn++;
			    }
			    if ( $qn >= 3 ) {
				for(my $si = $m-1; $m - $si <= $qn; $si--) {
				    $sclip5{ $start }->{ nt }->[$m-1-$si]->{ substr($a[9], $si, 1) }++;
				    $sclip5{ $start }->{ seq }->[$m-1-$si]->{ substr($a[9], $si, 1) }->{ cnt } = 0 unless( $sclip5{ $start }->{ seq }->[$m-1-$si]->{ substr($a[9], $si, 1) }->{ cnt });
				    addCnt($sclip5{ $start }->{ seq }->[$m-1-$si]->{ substr($a[9], $si, 1) }, $dir, $si - ($m-$qn), ord(substr($a[10], $si, 1))-33, $a[4]);
				}
				$sclip5{ $start }->{ cnt } = 0 unless( $sclip5{ $start }->{ cnt } );
				addCnt( $sclip5{ $start }, $dir, $m, $q, $a[4]);
			    }
			    #}
			}
			$m = $cigar[$ci];
		    } elsif ( $ci == @cigar - 2 ) { # 3' soft clipped
			while( $n < length($a[9]) && $REF{ $start } eq substr($a[9], $n, 1) && ord(substr($a[10], $n, 1))-33 > 10) {
			    $hash{ $start }->{ $REF{ $start } }->{ cnt } = 0 unless( $hash{ $start }->{ $REF{ $start } }->{ cnt } );
			    addCnt($hash{ $start }->{ $REF{ $start } }, $dir, $rlen2-$p, ord(substr($a[10], $n, 1))-33, $a[4]);
			    $cov{$start}++;
			    $n++; $start++; $m--; $p++;
			}
			if ( length($a[9]) - $n > 0 ) {
			    my $q = ord(substr($a[10], $n, 1))-33;
			    #unless (islowqual(substr($a[10], $n))) {
			    my $qn = 0;
			    for(my $si = 0; $si < $m; $si++) {
				 last if (ord(substr($a[10], $n+$si, 1))-33 < 7);
				 $qn++;
			    }
			    if ( $qn > 3 ) {
				for(my $si = 0; $si < $qn; $si++) {
				    $sclip3{ $start }->{ nt }->[$si]->{ substr($a[9], $n+$si, 1) }++;
				    $sclip3{ $start }->{ seq }->[$si]->{ substr($a[9], $n+$si, 1) }->{ cnt } = 0 unless( $sclip3{ $start }->{ seq }->[$si]->{ substr($a[9], $n+$si, 1) }->{ cnt } );
				    addCnt($sclip3{ $start }->{ seq }->[$si]->{ substr($a[9], $n+$si, 1) }, $dir, $qn - $si, ord(substr($a[10], $n+$si, 1))-33, $a[4]);
				}
				$sclip3{ $start }->{ cnt } = 0 unless( $sclip3{ $start }->{ cnt } );
				addCnt( $sclip3{ $start }, $dir, $m, $q, $a[4] );
			    }
			    #}
			}
		    }
		    $n += $m;
		    $offset = 0;
		    next;
		} elsif ( $C eq "H" ) {
		    next;
		} elsif ( $C eq "I" ) {
		    my $s = substr($a[9], $n, $m);
		    my $q = substr($a[10], $n, $m);
		    my $ss = "";
                    my ($multoffs, $multoffp) = (0, 0); # For multiple indels within 10bp
                    if ( $cigar[$ci+2] && $cigar[$ci+2] <= $VEXT && $cigar[$ci+3] =~ /M/ && $cigar[$ci+5] && $cigar[$ci+5] =~ /[ID]/ ) {
                        $s .= "#" . substr($a[9], $n+$m, $cigar[$ci+2]);
                        $q .= substr($a[10], $n+$m, $cigar[$ci+2]); 
                        $s .= $cigar[$ci+5] eq "I" ? ("^" . substr($a[9], $n+$m+$cigar[$ci+2], $cigar[$ci+4])) : ("^" . $cigar[$ci+4]);
                        $q .= $cigar[$ci+5] eq "I" ? substr($a[10], $n+$m+$cigar[$ci+2], $cigar[$ci+4]) : substr($a[10], $n+$m+$cigar[$ci+2], 1);
                        $multoffs += $cigar[$ci+2] + ($cigar[$ci+5] eq "D" ? $cigar[$ci+4] : 0);
                        $multoffp += $cigar[$ci+2] + ($cigar[$ci+5] eq "I" ? $cigar[$ci+4] : 0);
                        $ci += 4;
		    } else {
			if ( $cigar[$ci+3] && $cigar[$ci+3] =~ /M/ ) {
			    for(my $vi = 0; $vi < $VEXT && $vi < $cigar[$ci+2]; $vi++) {
				last if ( substr($a[9], $n+$m+$vi, 1) eq "N" );
			        $offset = $vi+1 if ($REF{ $start+$vi } && substr($a[9], $n+$m+$vi, 1) ne $REF{ $start+$vi });
			    }
			    if ($offset) {
			        $ss .= substr($a[9], $n+$m, $offset);
				$q .= substr($a[10], $n+$m, $offset);
			    }
			}
		    }
		    $s = "$s&$ss" if ( $offset > 0);
		    $ins{ $start - 1 }->{ "+$s" }++;
		    if ( $start - 1 >= $START && $start -1 <= $END && $s !~ /N/ ) {
			$hash{ $start - 1 }->{ I }->{ "+$s" }->{ $dir }++;
			my $hv = $hash{ $start - 1 }->{ I }->{ "+$s" };
			$hv->{ cnt }++;
			my $tp = $p < $rlen-$p ? $p + 1: $rlen-$p;
			my $tmpq = 0;
			for(my $i = 0; $i < length($q); $i++) {
			    $tmpq += ord(substr($q, $i, 1))-33; 
			}
			$tmpq /= length($q);
			unless( $hv->{ pstd } ) {
			    $hv->{ pstd } = 0;
			    $hv->{ pstd } = 1 if ($hv->{ pp } && $tp != $hv->{ pp });
			}
			unless( $hv->{ qstd } ) {
			    $hv->{ qstd } = 0;
			    $hv->{ qstd } = 1 if ($hv->{ pq } && $tmpq != $hv->{ pq });
			}
			$hv->{ pmean } += $tp;
			$hv->{ qmean } += $tmpq;
			$hv->{ Qmean } += $a[4];
			$hv->{ pp } = $tp;
			$hv->{ pq } = $tmpq;
			$tmpq >= $GOODQ ? $hv->{ hicnt }++ : $hv->{ locnt }++;
			if ( $hash{ $start - 1 }->{ $REF{ $start - 1 } } && substr($a[9], $n-1, 1) eq $REF{ $start - 1 } ) {
			    subCnt($hash{ $start - 1 }->{ $REF{ $start - 1 } }, $dir, $tp, $tmpq, $a[4]);
			}
			# Adjust count if the insertion is at the edge so that the AF won't > 1
			if ( $ci == 2 && $cigar[1] =~ /S|H/ ) {
			    my $ttref = $hash{ $start - 1 }->{ $REF{ $start - 1 } };
			    $ttref->{ $dir }++;
			    $ttref->{ cnt }++;
			    $ttref->{ pstd } = $hv->{ pstd };
			    $ttref->{ qstd } = $hv->{ qstd };
			    $ttref->{ pmean } += $tp;
			    $ttref->{ qmean } += $tmpq;
			    $ttref->{ Qmean } += $a[4];
			    $ttref->{ pp } = $tp;
			    $ttref->{ pq } = $tmpq;
			    #$cov{ $start - 1 }->{ $REF{ $start - 1 } }++;
			    $cov{ $start - 1 }++;
			}

		    }
		    $n += $m+$offset+$multoffp;
		    $p += $m+$offset+$multoffp;
		    $start += $offset+$multoffs;
		    next;
		} elsif ( $C eq "D" ) {
		    my $s = "-$m";
		    my $ss = "";
                    my $q = substr($a[10], $n, 1);
                    my ($multoffs, $multoffp) = (0, 0); # For multiple indels within $VEXT bp 
                    if ( $cigar[$ci+2] && $cigar[$ci+2] <= $VEXT && $cigar[$ci+3] =~ /M/ && $cigar[$ci+5] && $cigar[$ci+5] =~ /[ID]/ ) {
                        $s .= "#" . substr($a[9], $n, $cigar[$ci+2]);
                        $q .= substr($a[10], $n, $cigar[$ci+2]);
                        $s .= $cigar[$ci+5] eq "I" ? ("^" . substr($a[9], $n+$cigar[$ci+2], $cigar[$ci+4])) : ("^" . $cigar[$ci+4]);
                        $q .= $cigar[$ci+5] eq "I" ? substr($a[10], $n+$cigar[$ci+2], $cigar[$ci+4]) : "";
                        $multoffs += $cigar[$ci+2] + ($cigar[$ci+5] eq "D" ? $cigar[$ci+4] : 0);
                        $multoffp += $cigar[$ci+2] + ($cigar[$ci+5] eq "I" ? $cigar[$ci+4] : 0);
                        $ci += 4;
                    } else {
			if ( $cigar[$ci+3] && $cigar[$ci+3] =~ /M/ ) {
			    for(my $vi = 0; $vi < $VEXT && $vi < $cigar[$ci+2]; $vi++) {
				last if ( substr($a[9], $n+$vi, 1) eq "N" );
			        $offset = $vi+1 if ($REF{ $start+$m+$vi } && substr($a[9], $n+$vi, 1) ne $REF{ $start+$m+$vi });
			    }
			    if ($offset) {
			        $ss .= substr($a[9], $n, $offset);
				$q .= substr($a[10], $n, $offset);
			    }
			}
		    }
		    $s = "$s&$ss" if ( $offset > 0 );
		    $q .= substr($a[10], $n+$offset, 1);
		    if ( $start >= $START && $start <= $END ) {
			$hash{ $start }->{ $s }->{ $dir }++;
			$dels5{ $start }->{ $s }++;
			my $hv = $hash{ $start }->{ $s };
			$hv->{ cnt }++;
			my $tp = $p < $rlen-$p ? $p + 1: $rlen-$p;
			my $tmpq = 0;
			for(my $i = 0; $i < length($q); $i++) {
			    $tmpq += ord(substr($q, $i, 1))-33; 
			}
			$tmpq /= length($q);
			unless( $hv->{ pstd } ) {
			    $hv->{ pstd } = 0;
			    $hv->{ pstd } = 1 if ($hv->{ pp } && $tp != $hv->{ pp });
			}
			unless( $hv->{ qstd } ) {
			    $hv->{ qstd } = 0;
			    $hv->{ qstd } = 1 if ($hv->{ pq } && $tmpq != $hv->{ pq });
			}
			$hv->{ pmean } += $tp;
			$hv->{ qmean } += $tmpq;
			$hv->{ Qmean } += $a[4];
			$hv->{ pp } = $tp;
			$hv->{ pq } = $tmpq;
			$tmpq >= $GOODQ ? $hv->{ hicnt }++ : $hv->{ locnt }++;
			for(my $i = 0; $i < $m; $i++) {
			    #$cov{ $start+$i }->{ $s }++;
			    $cov{ $start+$i }++;
			}
		    }
		    $start += $m+$offset+$multoffs;
		    $n += $offset+$multoffp;
		    $p += $offset+$multoffp;
		    next;
		}
		for(my $i = $offset; $i < $m; $i++) {
		    my $trim = 0;
		    if ( $opt_T ) {
		        if ( $dir eq "+" ) {
			    $trim = 1 if ( $n > $opt_T );
			} else {
			    $trim = 1 if ( $rlen2 - $n > $opt_T );
			}
		    }
		    my $s = substr($a[9], $n, 1);
		    if ( $s eq "N" ) {
		        $start++; $n++; $p++;
			next;
		    }
                    my $q = ord(substr($a[10], $n, 1))-33;
                    # for more than one nucleotide mismatch
		    my $ss = "";
                    while(($start + 1) >= $START && ($start + 1) <= $END && ($i + 1) < $m && substr($a[9], $n, 1) ne $REF{$start} ) {
			last if (substr($a[9], $n+1, 1) eq "N" );
                        if ( substr($a[9], $n+1, 1) ne $REF{ $start + 1 } ) {
                            $ss .= substr($a[9], $n+1, 1);
                            $q += ord(substr($a[10], $n+1, 1))-33;
                            $n++;
                            $p++;
                            $i++;
                            $start++;
                        } else {
                            last;
                        }
                    }
		    $s .= "&$ss" if ( $ss );
		    unless( $trim ) {
			if ( $start - length($ss) >= $START && $start - length($ss) <= $END ) {
			    $hash{ $start - length($ss) }->{ $s }->{ $dir }++;
			    my $hv = $hash{ $start - length($ss) }->{ $s };
			    $hv->{ cnt }++;
			    my $tp = $p < $rlen-$p ? $p + 1: $rlen-$p;
			    $q = $ss? $q/(length($s)-1) : $q;
			    unless( $hv->{ pstd } ) {
				$hv->{ pstd } = 0;
				$hv->{ pstd } = 1 if ($hv->{ pp } && $tp != $hv->{ pp });
			    }
			    unless( $hv->{ qstd } ) {
				$hv->{ qstd } = 0;
				$hv->{ qstd } = 1 if ($hv->{ pq } && $q != $hv->{ pq });
			    }
			    $hv->{ pmean } += $tp;
			    $hv->{ qmean } += $q;
			    $hv->{ Qmean } += $a[4];
			    $hv->{ pp } = $tp;
			    $hv->{ pq } = $q;
			    $q >= $GOODQ ? $hv->{ hicnt }++ : $hv->{ locnt }++;
			    #$cov{ $start - length($ss) }->{ $s }++;
			    $cov{ $start - length($ss) }++;
			}
		    }
		    $start++ unless( $C eq "I" );
		    $n++ unless( $C eq "D" );
		    $p++ unless( $C eq "D" );
		}
		$offset = 0;
	    }
	}
	close( SAM );
    }

    if ( $opt_k ) {
        realigndel(\%hash, \%dels5, \%cov, \%sclip5, \%sclip3, \%REF, $chr);
        realignins(\%hash, \%ins, \%cov, \%sclip5, \%sclip3, \%REF, $chr);
        realignlgdel(\%hash, \%cov, \%sclip5, \%sclip3, \%REF, $chr);
        realignlgins(\%hash, \%cov, \%sclip5, \%sclip3, \%REF, $chr);
    }

    # 
    my %vars; # the variant structure
    while( my ($p, $v) = each %hash ) {
	my @tmp = ();
	my $vcov = 0; #the variance coverage
	my @var = ();
	my @vn = keys %$v;
	#if ( @vn == 1 && $vn[0] eq $REF{ $p } ) {
	#    next unless( $opt_p ); # ignore if only reference were seen and no pileup to avoid computation
	#}
	#my @v = values %{ $cov{ $p } };
	#my $tcov = 0; $tcov += $_ foreach(@v); #$stat->sum(\@v);
	next unless ( $cov{ $p } );
	my $tcov = $cov{ $p };
	my $hicov = 0;
	$hicov += $_->{ hicnt } ? $_->{ hicnt } : 0 foreach( values %$v );
	next if ( $tcov == 0 ); # ignore when there's no coverage
	while( my ($n, $cnt) = each %$v ) {
	    unless( $n eq "I") {
		next unless( $cnt->{ cnt } );
		my $fwd = $cnt->{ "+" } ? $cnt->{ "+" } : 0;
		my $rev = $cnt->{ "-" } ? $cnt->{ "-" } : 0;
		my $bias = strandBias($fwd, $rev);
		my $vqual = sprintf("%.1f", $cnt->{ qmean }/$cnt->{ cnt }); # base quality
		my $MQ = sprintf("%.1f", $cnt->{ Qmean }/$cnt->{ cnt }); # mapping quality
		my ($hicnt, $locnt) = ($cnt->{ hicnt } ? $cnt->{ hicnt } : 0, $cnt->{ locnt } ? $cnt->{ locnt } : 0);
		my $tvref = {n => $n, cov => $cnt->{ cnt }, fwd => $fwd, rev => $rev, bias => $bias, freq => ($fwd+$rev)/$tcov, pmean => sprintf("%.1f", $cnt->{ pmean }/$cnt->{ cnt } ), pstd => $cnt->{ pstd }, qual => $vqual, qstd => $cnt->{ qstd }, mapq => $MQ, qratio => sprintf("%.3f", $hicnt/($locnt ? $locnt : $locnt+0.5)), hifreq => ($hicov > 0 ? $hicnt/$hicov : 0), extrafreq => $cnt->{ extracnt } ? $cnt->{ extracnt }/$tcov : 0, shift3 => 3, msi => 0 };
		push(@var, $tvref);
		if ( $opt_D ) {
		    push( @tmp, "$n:" . ($fwd + $rev) . ":F-$fwd:R-$rev:" . sprintf("%.5f", $tvref->{freq}) . ":$tvref->{bias}:$tvref->{pmean}:$tvref->{pstd}:$vqual:$tvref->{qstd}:" . sprintf("%.5f", $tvref->{hifreq}) . ":$tvref->{mapq}:$tvref->{qratio}");
		}
	    }
	}
	if ( $v->{ I } ) {
	    while( my ($n, $cnt) = each %{ $v->{ I } } ) {
		my $fwd = $cnt->{ "+" } ? $cnt->{ "+" } : 0;
		my $rev = $cnt->{ "-" } ? $cnt->{ "-" } : 0;
		my $bias = strandBias($fwd, $rev);
		my $vqual = sprintf("%.1f", $cnt->{ qmean }/$cnt->{ cnt }); # base quality
		my $MQ = sprintf("%.1f", $cnt->{ Qmean }/$cnt->{ cnt }); # mapping quality
		my ($hicnt, $locnt) = ($cnt->{ hicnt } ? $cnt->{ hicnt } : 0, $cnt->{ locnt } ? $cnt->{ locnt } : 0);
		my $tvref = {n => $n, cov => $cnt->{ cnt }, fwd => $fwd, rev => $rev, bias => $bias, freq => ($fwd+$rev)/$tcov, pmean => sprintf("%.1f", $cnt->{ pmean }/$cnt->{ cnt } ), pstd => $cnt->{ pstd }, qual => $vqual, qstd => $cnt->{ qstd }, mapq => $MQ, qratio => sprintf("%.3f", $hicnt/($locnt ? $locnt : $locnt+0.5)), hifreq => ($hicov > 0 ? $hicnt/$hicov : 0), extrafreq => 0, shift3 => 3, msi => 0 };
		push(@var, $tvref);
		if ( $opt_D ) {
		    push( @tmp, "I$n:" . ($fwd + $rev) . ":F-$fwd:R-$rev:" . sprintf("%.5f", $tvref->{freq}) . ":$tvref->{bias}:$tvref->{pmean}:$tvref->{pstd}:$vqual:$tvref->{qstd}:" . sprintf("%.5f", $tvref->{hifreq}) . ":$tvref->{mapq}:$tvref->{qratio}" );
		}
	    }
	}
	@var = sort { $b->{ qual } * $b->{cov} <=> $a->{ qual } * $a->{cov}; } @var;
	foreach my $tvar (@var) {
	    if ( $tvar->{ n } eq $REF{ $p } ) {
	        $vars{ $p }->{ REF } = $tvar;
	    } else {
	        push( @{ $vars{ $p }->{ VAR } }, $tvar );
		$vars{ $p }->{ VARN }->{ $tvar->{ n } } = $tvar;
	    }
	}
	# Make sure the first bias is always for the reference nucleotide
	my ($pmean, $pstd, $qual, $qstd, $mapq, $qratio);
	my ($rfc, $rrc) = (0, 0); # coverage for referece forward and reverse strands
	my $genotype1 = $vars{ $p }->{ REF } && $vars{ $p }->{ REF }->{ freq } >= $FREQ ? $vars{ $p }->{ REF }->{ n } : $vars{ $p }->{ VAR } ? $vars{ $p }->{ VAR }->[0]->{ n } : $vars{ $p }->{ REF }->{ n };
	my $genotype2 = "";
	my $vn;

	if ( $vars{ $p }->{ REF } ) {
	    ($rfc, $rrc) = ($vars{ $p }->{ REF }->{ fwd }, $vars{ $p }->{ REF }->{ rev });
	}
	# only reference reads are observed.
	if ( $vars{ $p }->{ VAR } ) {
	    for(my $vi = 0; $vi < @{ $vars{ $p }->{ VAR } }; $vi++) {
		my $vref = $vars{ $p }->{ VAR }->[$vi];
		$genotype2 = $vref->{ n };
		$vn = $vref->{ n };
		my $dellen = $vn =~ /^-(\d+)/ ? $1 : 0;
		my $ep = $vn =~ /^\+/ ?  $p : ($vn =~ /^-/ ? $p + $dellen - 1: $p);
		my ($refallele, $varallele) = ("", "");
		my ($shift3, $msi) = (0, 0);  # how many bp can a deletion be shifted to 3 prime
		my $sp = $p;
		if ( $vn =~ /^\+/ ) {
=head2 insRealign
		    if ( $opt_k && $vref->{ cov } >= $MINR ) {
			my $extra = ($vn =~ /&([ATGC]+)/) ? $1 : "";
			my $wupseq = join( "", (map { $REF{ $_ }; } (($p - $opt_k - length($vn)+1) .. $p))) . $vn; # 5prime flanking seq
			$wupseq =~ s/\+//;
			my $sanpseq = $vn . $extra . join( "", (map { $REF{ $_ }; } (($p + length($extra)+1) .. ($p + length($vn) + $opt_k)))); # 3prime flanking seq
			$sanpseq =~ s/^\+//;
			for( my $tp5 = $p - $opt_k - length($vn); $tp5 <= $p + length($vn)+$opt_k; $tp5++) {
			    next unless( $hash{ $tp5 } );
			    while( my ($tn, $tv) = each %{ $hash{ $tp5 } }) {
				next if ($tn eq $REF{ $tp5 });
				next if ( $tn eq "I" );
				next if ( $tn =~ /^-/ );
				next if ( $tv->{ qmean }/$tv->{ cnt } < $GOODQ );
				#print STDERR "InDel Realign: $p $tp5 ", $tv->{ pmean }/$tv->{ cnt }, "\t", $tv->{ cnt }, "\t", length($vn), "\t", int(length($vn)/2) + 2, "\n";
				#next if ( $tv->{ pmean }/$tv->{ cnt } > int(length($vn)/2) + 2); # $opt_k;
				next if ( $tv->{ pmean }/$tv->{ cnt } > 4); # $opt_k;
				my $head = $tn;
				$head =~ s/&//;
				$head =~ s/^\+//;
				my $flag = 0;
				$flag = 3 if ( $tp5 == $p + 1 && $sanpseq =~ /^$head/ );
				$flag = 5 if ( $tp5 + length($head) == $p + 1 + length($extra) && $wupseq =~ /$head$/);
				#print STDERR join("\t", $tn, $head, $p, $tp5, $extra, $flag, $wupseq, $sanpseq), "\n";
				if ( $flag ) {
				    $tcov += $tv->{ cnt } if ( $flag == 5 );
				    $vref->{ extrafreq } += $tv->{ cnt }/$tcov;
				    $vref->{ hifreq } += $hicov > 0 ? $tv->{ hicnt }/$hicov : 0;
				    $vref->{ fwd } += $tv->{ "+" } ? $tv->{ "+" } : 0;
				    $vref->{ rev } += $tv->{ "-" } ? $tv->{ "-" } : 0;
				    $vref->{ cov } += ($tv->{ "+" } ? $tv->{ "+" } : 0) + ($tv->{ "-" } ? $tv->{ "-" } : 0);
				    $vref->{ freq } = $vref->{ cov }/$tcov;
				}
			    }
			}
		    }
=cut
		    unless( $vn =~ /&/ || $vn =~ /#/ ) {
			my $tseq1 = $vn;
			$tseq1 =~ s/^\+//;
			my $tseq2 = join("", (map { $REF{ $_ }; } (($p+1) .. ($p+length($tseq1)))));
			while( $tseq1 eq $tseq2 ) {
			    $shift3 += length($tseq1);
			    $p += length($tseq1);
			    $tseq2 = join("", (map { $REF{ $_ }; } (($p+1) .. ($p+length($tseq1)))));
			}
			$msi = $shift3/length($tseq1);
		    }
		    if ( $opt_3 ) {
			$sp += $shift3;
			$ep += $shift3;
		    } else {
			$p -= $shift3;
		    }
		    ($refallele, $varallele) = ($REF{$p}, $vn);
		    $varallele =~ s/^\+//;
		    $varallele = $REF{$p} . $varallele;
		} elsif ( $vn =~ /^-/ ) {
		    $varallele = $vn;
		    $varallele =~ s/^-\d+//;
		    unless( $vn =~ /&/ || $vn =~ /#/ ) {
			while($REF{ $sp } eq $REF{ $ep+1 } ) {
			    $sp++;
			    $ep++;
			    $p++;
			    $shift3++;
			}
			$msi = $shift3/$dellen; # if ( $shift3%$dellen == 0 );
			unless ( $opt_3 ) {
			    $sp -= $shift3;
			    $ep -= $shift3;
			    $p -= $shift3;
			}
			$varallele = $REF{ $p - 1 };
			$refallele = $REF{ $p - 1 };
			$sp--;
		    }
		    for(my $i = 0; $i < $dellen; $i++) {
			$refallele .= $REF{ $p + $i };
		    }
		} else {
		    ($refallele, $varallele) = ($REF{ $p }, $vn);
		}
		if ( $vn =~ /&(.*)$/ ) {
		    my $extra = $1;
		    $varallele =~ s/&//;
		    for(my $m = 0; $m < length($extra); $m++) {
			$refallele .= $REF{ $ep + $m + 1 };
			$genotype1 .= $REF{ $ep + $m + 1 } unless( $genotype1 =~ /^-/ || $genotype1 =~ /^\+/ || length($genotype1) > 1 );
		    }
		    $ep += length($extra);
		    if ( $vn =~ /^\+/ ) {
		        substr($refallele, 0, 1) = "";
		        substr($varallele, 0, 1) = "";
			$sp++;
		    }
		}
		if ($vn =~ /#(.+)\^(.+)/) {
		    my $mseq = $1;
		    my $tail = $2;
		    $ep += length($mseq);
		    $refallele .= join("", (map { $REF{ $_ }; } (($ep-length($mseq)+1) .. $ep)));
		    if ( $tail =~ /^(\d+)/ ) {
			for(my $ti = 0; $ti < $1; $ti++) {
			    $refallele .= $REF{ $ep + $ti + 1 };
			}
			$ep += $1;
		    }
		    $varallele =~ s/#//;
		    $varallele =~ s/\^(\d+)?//;
		    $genotype1 =~ s/#/m/;
		    $genotype1 =~ s/\^/-/;
		    $genotype2 =~ s/#/m/;
		    $genotype2 =~ s/\^/-/;
		}
		$vref->{ leftseq } = join( "", (map { $REF{ $_ }; } (($sp - 10) .. ($sp - 1))) ); # left 10 nt
		$vref->{ rightseq } = join( "", (map { $REF{ $_ }; } (($ep + 1) .. ($ep + 10))) ); # right 10 nt
		my $genotype = "$genotype1/$genotype2";
		$genotype =~ s/&//g;
		$genotype =~ s/#//g;
		$genotype =~ s/\^/-/g;
		$vref->{ extrafreq } = sprintf("%.5f", $vref->{ extrafreq } ) if ($vref->{ extrafreq });
		$vref->{ freq } = sprintf("%.5f", $vref->{ freq }) if ($vref->{ freq });
		$vref->{ hifreq } = sprintf("%.5f", $vref->{ hifreq }) if ($vref->{ hifreq });
		$vref->{ msi } = $msi ? sprintf("%.3f", $msi) : $msi;
		$vref->{ shift3 } = $shift3;
		$vref->{ sp } = $sp;
		$vref->{ ep } = $ep;
		$vref->{ refallele } = $refallele;
		$vref->{ varallele } = $varallele;
		$vref->{ genotype } = $genotype;
		$vref->{ tcov } = $tcov;
		$vref->{ rfc } = $rfc;
		$vref->{ rrc } = $rrc;
		$vref->{ bias } = $vars{$p}->{ REF } ? $vars{$p}->{ REF }->{ bias } . ";" . $vref->{ bias } : "0;" . $vref->{ bias };
		$vref->{ DEBUG } = join(" & ", @tmp) if ( $opt_D );
	    }
	}
	if ( $vars{$p}->{ REF } ) {
	    my $vref = $vars{$p}->{ REF };  # no variant reads are detected.
	    $vref->{ tcov } = $tcov;
	    $vref->{ cov } = 0;
	    $vref->{ freq } = 0;
	    $vref->{ rfc } = $rfc;
	    $vref->{ rrc } = $rrc;
	    $vref->{ fwd } = 0;
	    $vref->{ rev } = 0;
	    $vref->{ msi } = 0;
	    $vref->{ bias } .= ";0";
	    $vref->{ shift3 } = 0;
	    $vref->{ sp } = $p;
	    $vref->{ ep } = $p;
	    $vref->{ hifreq } = sprintf("%.5f", $vref->{ hifreq }) if ($vref->{ hifreq });
	    $vref->{ refallele } = $REF{$p};
	    $vref->{ varallele } = $REF{$p};
	    $vref->{ genotype } = "$REF{$p}/$REF{$p}";
	    $vref->{ leftseq } = "";
	    $vref->{ rightseq } = "";
	    $vref->{ DEBUG } = join(" & ", @tmp) if ( $opt_D );
        }
    }
    return \%vars;
}

sub islowqual {
    my $q = shift;
    for(my $i = 0; $i < length($q); $i++) {
       return 1 if(ord(substr($q,$i,1))-33 < 7 && length($q) - $i > 3);
    }
    return 0;
}

# if any of the base is represented by 75%, it's a low complexity seq
sub islowcomplexseq {
    my ($seq) = @_;
    my $len = length($seq);
    return 1 if ( $len == 0 );
    my $a = $seq =~ s/A/A/g;
    return 1 if ( $a/$len > 0.75 );
    my $t = $seq =~ s/T/T/g;
    return 1 if ( $t/$len > 0.75 );
    my $g = $seq =~ s/G/G/g;
    return 1 if ( $g/$len > 0.75 );
    my $c = $seq =~ s/C/C/g;
    return 1 if ( $c/$len > 0.75 );
    return 0;
}
# Realign large insertions that are not present in alignment
sub realignlgins {
    my ($hash, $cov, $sclip5, $sclip3, $REF, $chr) = @_;
    my $LONGMM = 3;
    my @tmp;
    while(my($p, $sc5v) = each %$sclip5) {
        push(@tmp, [$p, $sc5v, $sc5v->{cnt}]);
    }
    @tmp = sort {$b->[2] <=> $a->[2];} @tmp;
    foreach my $t (@tmp) {
	my ($p, $sc5v, $cnt) = @$t;
	next if ($sc5v->{ used }); # already been used in realigndel subroutine
	my $seq = findconseq($sc5v);
	next unless( $seq );
	next if ($seq =~ /^.AAAAAAA/ || $seq =~ /^.TTTTTTT/ );
	next if ( length($seq) < 15 );
	next if ( islowcomplexseq($seq) );
	my ($bi, $ins) = findbi($seq, $p, $REF, -1, $chr);
	next unless( $bi );
	#print STDERR "5: $bi $ins $p $seq\n";
	$hash->{ $bi }->{ I }->{ "+$ins" }->{ cnt } = 0 unless( $hash->{ $bi }->{ I }->{ "+$ins" }->{ cnt } );
	$hash->{ $bi }->{ I }->{ "+$ins" }->{ pstd } = 1;
	$hash->{ $bi }->{ I }->{ "+$ins" }->{ qstd } = 1;
	    #print STDERR "5B: $bi $cov->{ $bi } $sc5v->{cnt}\n";
	adjCnt($hash->{ $bi }->{ I }->{ "+$ins" }, $sc5v);
	$cov->{ $bi } += $sc5v->{ cnt };
	my $len = $ins =~ /&/ ? length($ins) - 1 : length($ins);
	for(my $ii = $len+1; $ii < @{ $sc5v->{ seq } }; $ii++) {
	    my $pii = $bi - $ii + $len;
	    while(my( $tnt, $tv) = each %{ $sc5v->{ seq }->[$ii] }) {
		$hash->{ $pii }->{ $tnt }->{ cnt } = 0 unless( $hash->{ $pii }->{ $tnt }->{ cnt } );
		adjCnt( $hash->{ $pii }->{ $tnt }, $tv );
		$hash->{ $pii }->{ $tnt }->{ pstd } = 1;
		$hash->{ $pii }->{ $tnt }->{ qstd } = 1;
		$cov->{ $pii } += $tv->{ cnt };
	    }
	}
	$sc5v->{ used } = 1;
	    #print STDERR "5A: $bi $cov->{ $bi } $sc5v->{cnt}\n";
    }
    @tmp = ();
    while(my($p, $sc3v) = each %$sclip3) {
        push(@tmp, [$p, $sc3v, $sc3v->{cnt}]);
    }
    @tmp = sort {$b->[2] <=> $a->[2];} @tmp;
    foreach my $t (@tmp) {
	my ($p, $sc3v, $cnt) = @$t;
	next if ($sc3v->{ used }); # already been used in realigndel subroutine
	my $seq = findconseq($sc3v);
	next unless( $seq );
	next if ($seq =~ /^.AAAAAAA/ || $seq =~ /^.TTTTTTT/ );
	next if ( length($seq) < 15 );
	next if ( islowcomplexseq($seq) );
	my ($bi, $ins, $be) = findbi($seq, $p, $REF, 1, $chr);
	next unless( $bi );
	#print STDERR "3: $bi $ins $p $seq\n";
	$hash->{ $bi }->{ I }->{ "+$ins" }->{ cnt } = 0 unless( $hash->{ $bi }->{ I }->{ "+$ins" }->{ cnt } );
	$hash->{ $bi }->{ I }->{ "+$ins" }->{ pstd } = 1;
	$hash->{ $bi }->{ I }->{ "+$ins" }->{ qstd } = 1;
	    #print STDERR "3B: $bi $cov->{ $bi } $ins $sc3v->{cnt}\n";
	adjCnt($hash->{ $bi }->{ I }->{ "+$ins" }, $sc3v, $hash->{ $bi }->{ $REF->{ $bi } });
	my $offset = $bi == $be ? ($p - $bi - 1) : -($p + $be - $bi);
	my $len = $ins =~ /&/ ? length($ins) - 1 : length($ins);
	for(my $ii = $len-$offset; $ii < @{ $sc3v->{ seq } }; $ii++) {
	    my $pii = $p + $ii - $len;
	    while(my( $tnt, $tv) = each %{ $sc3v->{ seq }->[$ii] }) {
		$hash->{ $pii }->{ $tnt }->{ cnt } = 0 unless( $hash->{ $pii }->{ $tnt }->{ cnt } );
		adjCnt( $hash->{ $pii }->{ $tnt }, $tv );
		$hash->{ $pii }->{ $tnt }->{ pstd } = 1;
		$hash->{ $pii }->{ $tnt }->{ qstd } = 1;
		$cov->{ $pii } += $tv->{ cnt };
	    }
	}
	$sc3v->{ used } = 1;
	    #print STDERR "3A: $bi $cov->{ $bi } $sc3v->{cnt}\n";
    }
}

# Realign large deletions that are not present in alignment
sub realignlgdel {
    my ($hash, $cov, $sclip5, $sclip3, $REF, $chr) = @_;
    my $LONGMM = 3;
    my @tmp;
    while(my($p, $sc5v) = each %$sclip5) {
        push(@tmp, [$p, $sc5v, $sc5v->{cnt}]);
    }
    @tmp = sort {$b->[2] <=> $a->[2];} @tmp;
    foreach my $t (@tmp) {
	my ($p, $sc5v, $cnt) = @$t;
        #next if ($cnt < $MINR);
	#use Object; print STDERR Object::Perl($sc5v);
	next if ($sc5v->{ used }); # already been used in realigndel subroutine
	my $seq = findconseq($sc5v);
	#print STDERR "LG: $seq\t\n";
	next unless( $seq );
	next if ($seq =~ /^.AAAAAAA/ || $seq =~ /^.TTTTTTT/ );
	next if ( length($seq) < 10 );
	next if ( islowcomplexseq($seq) );
	my $bp = findbp($seq, $p - 10, $REF, 120, -1, $chr);
	my $dellen = $p - $bp;
	next unless( $bp );
	my $extra = "";
	my $en = 0;
	while( substr($seq, $en, 1) ne $REF->{ $bp - $en - 1 } && $en < length($seq) ) {
	    $extra .= substr($seq, $en, 1);
	    $en++;
	}
	my $gt = -$dellen;
	if ( $extra ) {
	    #$gt = -($dellen - length($extra)+1) . "&$extra";
	    $gt = "-$dellen&$extra";
	    $bp -= length($extra);
	}
	$hash->{$bp}->{ $gt }->{ cnt } = 0 unless( $hash->{$bp}->{ $gt }->{ cnt } );
	$hash->{$bp}->{ $gt }->{ qstd } = 1; # more accurate implementation later
	$hash->{$bp}->{ $gt }->{ pstd } = 1; # more accurate implementation later
	for(my $tp = $bp; $tp < $bp + $dellen; $tp++) {
	    $cov->{$tp} += $sc5v->{ cnt };
	}
	adjCnt( $hash->{$bp}->{ $gt }, $sc5v );
	$sc5v->{ used } = 1;

	# Work on the softclipped read at 3'
	my $n = 0;
	$n++ while( $REF->{ $bp+$n } eq $REF->{ $bp + $dellen + $n} );
	my $sc3p = $bp + $n;
	my $str = "";
	my $mcnt = 0;
	while( $REF->{ $bp+$n } ne $REF->{ $bp + $dellen + $n} && $mcnt <= $LONGMM) {
	    $str .= $REF->{ $bp + $dellen + $n};
	    $n++; $mcnt++;
	}
	if ( length($str) == 1 ) {
	    $n++ while( $REF->{ $bp+$n } eq $REF->{ $bp + $dellen + $n} );
	    $sc3p = $bp + $n;
	}
	if ( $sclip3->{ $sc3p } && (! $sclip3->{ $sc3p }->{ used }) ) {
	    adjCnt($hash->{$bp}->{ $gt }, $sclip3->{ $sc3p }, $hash->{$bp}->{ $REF->{ $bp } });
	    for(my $ip = $bp+1; $ip < $sc3p; $ip++) {
	        rmCnt($hash->{$ip}->{ $REF->{$dellen + $ip} }, $sclip3->{$sc3p});
		delete $hash->{$ip}->{ $REF->{$dellen + $ip} } if ( $hash->{$ip}->{ $REF->{$dellen + $ip} } && $hash->{$ip}->{ $REF->{$dellen + $ip} }->{ cnt } == 0);
		delete $hash->{$ip} if ( (keys %{$hash->{$ip}} ) == 0);
	    }
	    $sclip3->{ $sc3p }->{ used } = 1;
	}
	my %dels5;
	$dels5{ $bp }->{$gt} = $hash->{$bp}->{ $gt }->{cnt};
	realigndel($hash, \%dels5, $cov, $sclip5, $sclip3, $REF, $chr);
    }
}

sub subCnt {
    my ($vref, $dir, $rp, $q, $Q) = @_;  # ref dir read_position quality
    $vref->{ cnt }--;
    $vref->{ $dir }--;
    $vref->{ pmean } -= $rp;
    $vref->{ qmean } -= $q;
    $vref->{ Qmean } -= $Q;
    $q >= $GOODQ ? $vref->{ hicnt }-- : $vref->{ locnt }--;
}

sub rmCnt {
    my ($vref, $tv) = @_;
    $vref->{ cnt } -= $tv->{ cnt };
    $vref->{ hicnt } -= $tv->{ hicnt } ? $tv->{ hicnt } : 0;
    $vref->{ locnt } -= $tv->{ locnt } ? $tv->{ locnt } : 0;
    $vref->{ pmean } -= $tv->{ pmean };
    $vref->{ qmean } -= $tv->{ qmean };
    $vref->{ Qmean } -= $tv->{ Qmean };
    $vref->{ "+" } -= $tv->{ "+" } ? $tv->{ "+" } : 0;
    $vref->{ "-" } -= $tv->{ "-" } ? $tv->{ "-" } : 0;
    foreach my $k (qw(cnt hicnt locnt pmean qmean Qmean + -)) {
        $vref->{ $k } = 0 if ( $vref->{ $k } && $vref->{ $k } < 0 );
    }
}

# Find the consensus sequence in soft-clipped reads
sub findconseq {
    my ($scv) = @_;
    #use Object; print STDERR "SUB: ", Object::Perl($scv), "\n";
    return $scv->{ SEQ } if ( $scv->{ SEQ } );
    return "" if (@{ $scv->{ nt } } < 3);  # At least 4 bp overhang needed
    my $total = 0;
    my $match = 0;
    my $seq = "";
    foreach my $nv (@{ $scv->{ nt } }) {
        my $max = 0;
	my $mnt = "";
	my $tt = 0;
	while(my ($nt, $ncnt) = each %$nv) {
	    $tt += $ncnt;
	    if ( $ncnt > $max ) {
		$max = $ncnt;
		$mnt = $nt;
	    }
	}
	#last if (($tt <  $MINR || $max <  $MINR) && $scv->{ cnt } >= $MINR);
	$total += $tt;
	$match += $max;
	$seq .= $mnt;
    }
    $scv->{ SEQ } = $seq;
    return ($total && $match/$total > 0.9) ? $seq : "";
}

# Find the insertion
sub findbi {
    my ($seq, $p, $REF, $dir, $chr) = @_;
    my $MAXMM = 2; # maximum mismatches allowed
    for(my $n = 6; $n < length($seq); $n++) {
        my $mm = 0;
	my $i = 0;
	my %m = ();
	last if ( $p + 6 >= $CHRS{ $chr } );
	for($i = 0; $i + $n < length($seq); $i++) {
	    last if ( $p + $dir*$i - ($dir == -1 ? 1 : 0) < 1 );
	    last if ( $p + $dir*$i - ($dir == -1 ? 1 : 0) > $CHRS{ $chr } );
	    $mm++ if ( substr($seq, $i + $n, 1) ne $REF->{ $p + $dir*$i - ($dir == -1 ? 1 : 0) } );
	    $m{ substr($seq, $i + $n, 1) }++;
	    last if ( $mm > $MAXMM );
	}
	my @mnt = keys %m;
	next unless( @mnt >= 3 ); # at least three different NT for overhang sequences, weeding out low complexity seq
	if ( $i + $n >= length($seq) - 1 && $i > 6 && $mm/$i < 0.2) {
	    my $ins = substr($seq, 0, $n);
	    my $extra = "";
	    my $ept = 0;
	    while(substr($seq, $n + $ept, 1) ne $REF->{ $p + $ept*$dir - ($dir == -1 ? 1 : 0) } || substr($seq, $n + $ept + 1, 1) ne $REF->{ $p + ($ept+1)*$dir - ($dir == -1 ? 1 : 0) }) {
		$extra .= substr($seq, $n + $ept, 1);
		$ept++;
	    }
	#print STDERR "bi: $n $i ", substr($seq, $n), " $p $seq $extra $ept $mm\n";
	    if ($dir == -1) {
		$ins .= $extra;
		$ins = reverse($ins);
		if ( $extra ) {
		    substr($ins, -length($extra), 0) = "&";
		}
		return ($p-1-length($extra), $ins, $p-1);
	    } else {
		my $s = -1;
		if ( $extra ) {
		    $ins .= "&$extra";
		} else {
		    while( substr($ins, $s, 1) eq $REF->{ $p + $s } && $s > -$n ) {
			$s--;
		    }
		    if ( $s < -1 ) {
			my $tins = substr($ins, $s + 1, 1 - $s);
			substr($ins, $s+1) = "";
			substr($ins, 0, 0) = $tins;
		    }
		}
		return($p+$s, $ins, $p+$s+length($extra));
	    }
	}
    }
    return (0, 0);
}

# Find breakpoint
sub findbp {
    my ($seq, $sp, $REF, $dis, $dir, $chr) = @_;
    my $MAXMM = 2; # maximum mismatches allowed
    for(my $n = 0; $n < $dis; $n++) {
	my $mm = 0;
	#next if (substr($seq, 0, 1) ne $REF->{ $sp + $dir*$n });
	my %m = ();
        for(my $i = 0; $i < length($seq) && $i < 50; $i++) {
	    last if ( $sp + $dir*$n + $dir*$i < 1 );
	    last if ( $sp + $dir*$n + $dir*$i > $CHRS{ $chr } );
	    $mm++ if ( substr($seq, $i, 1) ne $REF->{ $sp + $dir*$n + $dir*$i } );
	    $m{ substr($seq, $i, 1) }++;
	    last if ( $mm >  $MAXMM );
	}
	my @mnt = keys %m;
	next unless( @mnt >= 3 );
	return $sp + $dir*$n - ($dir < 0 ? $dir : 0) if ( $mm <= $MAXMM );
    }
    return 0;
}

# Realign deletions if already present in alignment
sub realigndel {
    my ($hash, $dels5, $cov, $sclip5, $sclip3, $REF, $chr) = @_;
    my $LONGMM = 3; # Longest continued mismatches typical aligned at the end
    while(my($p, $dv) = each %$dels5) {
        while(my($vn, $dcnt) = each %$dv) {
	    next unless( $dcnt >= $MINR );
	    my $vref = $hash->{ $p }->{ $vn };
	    my $dellen = $vn =~ /^-(\d+)/ ? $1 : 0;
	    my $extra = ($vn =~ /&([ATGC]+)/) ? $1 : "";
	    my $wupseq = join( "", (map { $REF->{ $_ }; } (($p - 2*$dellen - $opt_k - 10) .. ($p-1)))); # . $extra; # 5' flanking seq
	    my $sanpseq = $extra . join( "", (map { $REF->{ $_ }; } (($p + $dellen + length($extra)) .. ($p + 2*$dellen + $opt_k + 20)))); # 3' flanking seq
	    my @mm = (); # mismatches, mismatch positions, 5 or 3 ends
	    my $n = 0;
	    my $mn = 0;
	    my $mcnt = 0;
	    my $str = "";
	    my ($sc5p, $sc3p) = (0, 0); # for softclipping reads
	    $n++ while( $REF->{ $p+$n } eq substr($sanpseq, $n, 1) );
	    $sc3p = $p + $n;
	    while( $REF->{ $p+$n } ne substr($sanpseq, $n, 1) && $mcnt <= $LONGMM && $n < length($sanpseq)) {
		$str .= substr($sanpseq, $n, 1);
		push(@mm, [$str, $p + $n - length($str) + 1, 5]);
		$n++; $mcnt++;
	    }
	    if ( length($str) == 1 ) {
		$n++ && $mn++ while( $REF->{ $p+$n } eq substr($sanpseq, $n, 1) );
		$sc3p = $p + $n if ( $mn > 1 );
		$sclip3->{ $sc3p }->{ used } = 1 if ( $sclip3->{ $sc3p } && $mn > 1 && $dellen >= 4);
	    }
	    $n = 1;
	    $mn = 0;
	    $str = "";
	    $mcnt = length($extra);
	    push(@mm, [$extra, $p + $dellen, 3]) if ($extra);
	    $sc5p = $p + $dellen;
	    while( $REF->{ $p + $dellen - $n } ne substr($wupseq, -$n, 1) && $mcnt < $LONGMM ) {
		$str = substr($wupseq, -$n, 1) . $str;
		push(@mm, [$str . $extra, $p + $dellen - $n, 3] );
		$n++; $mcnt++;
	    }
	    if ( length($str) == 1 ) {
	        $n++ && $mn++ while( $REF->{ $p + $dellen - $n } eq substr($wupseq, -$n, 1) );
		$sc5p = $p + $dellen - $n + 1 if ($mn > 1);
		$sclip5->{ $sc5p }->{ used } = 1 if ( $sclip5->{ $sc5p } && $mn > 1 && $dellen >= 4);
	    }
	    #use Object; print STDERR "$p ", Object::Perl(\@mm);
	    for(my $mi = 0; $mi < @mm; $mi++) {
	        my ($mm, $mp, $me) = @{$mm[$mi]};
		substr($mm, 1, 0) = "&" if (length($mm) > 1);
		next unless( $hash->{ $mp } );
		next unless( $hash->{ $mp }->{ $mm } );
		my $tv = $hash->{ $mp }->{ $mm };
		next unless( $tv->{ cnt } );
		next if( $tv->{ qmean }/$tv->{ cnt } < $GOODQ );
		#print STDERR "InDel Realign: $p $mm $mp $me ", $tv->{ pmean }/$tv->{ cnt }, "\t", $tv->{ cnt }, "\t", $dellen, "\t", int($dellen/2) + 2, " $sc3p $sc5p $sanpseq $me\n";
		#next if ( $tv->{ pmean }/$tv->{ cnt } > int($dellen/2) + 2 ); #$opt_k;
		next unless ( $tv->{ pmean }/$tv->{ cnt } <= 4 || ($tv->{ pmean }/$tv->{ cnt } < $sc3p - $mp && $me == 5)); #$opt_k;
		#print STDERR $tv->{ pmean }/$tv->{ cnt }, " ", $sc3p - $mp, "\n";
		next unless( $tv->{ cnt } < $dcnt );
		# Adjust ref cnt so that AF won't > 1
		if ( $mp > $p && $me == 3 ) {
		    $cov->{ $p } += $tv->{ cnt };
		}

		my $ref = ($mp > $p && $me == 5) ? ($hash->{$p}->{ $REF->{$p} } ? $hash->{$p}->{ $REF->{$p} } : "") : "";
		#use Object; print STDERR "A: $mm $mp $me", Object::Perl($hash->{ $mp }), "\n", Object::Perl($ref), "\n";
		adjCnt($vref, $tv, $ref);
		#rmCnt($ref, $tv) if ( $mp > $p && $me == 5 && $ref);
		delete $hash->{ $mp }->{ $mm };
		delete $hash->{ $mp } if ( (keys %{$hash->{ $mp }} < 1) );
		#use Object; print STDERR "B: $mm $mp $me", Object::Perl($hash->{ $mp }), "\n", Object::Perl($ref), "\n";
		#rmCnt($hash->{ $mp }->{ $mm }, $hash->{ $mp }->{ $mm });
	    }

	    next if ( $dellen < 4 ); # soft-clipping only happens when deletion is at least 4 bp
	    if ( $sclip5->{ $sc5p } && (! $sclip5->{ $sc5p }->{ used }) ) {
		my $tv = $sclip5->{ $sc5p };
		my $seq = findconseq( $tv );
		#print STDERR $seq, "\t$sc5p, $p\t$tv->{cnt}\t", findbp($seq, $sc5p - $dellen - 1, $REF, 1, -1), "\n";
		if ( $seq && findbp($seq, $sc5p - $dellen - 1, $REF, 1, -1, $chr) ) {
		#print STDERR "5: $sc5p used\n";
		    $cov->{ $p } += $tv->{ cnt } if ( $sc5p > $p );
		    adjCnt($vref, $tv);
		    $sclip5->{ $sc5p }->{ used } = 1;
		}
	    }
	    if ( $sclip3->{ $sc3p } && (! $sclip3->{ $sc3p }->{ used }) ) {
		my $tv = $sclip3->{ $sc3p };
		my $seq = findconseq( $tv );
		#print STDERR "3: $sample $sc3p $seq $tv->{ cnt } used\n";
		#print STDERR $seq, "\t$sc3p, $p\t$tv->{cnt}\t", findbp($seq, $sc3p + $dellen, $REF, 1, 1), "\n";
		if ( $seq && findbp($seq, $sc3p + $dellen, $REF, 1, 1, $chr) ) {
		    $cov->{ $p } += $tv->{ cnt } if ( $sc3p <= $p );
		    my $ref = $sc3p <= $p ? "" : $hash->{$p}->{ $REF->{$p} };
		    adjCnt($vref, $tv, $ref);
		    $sclip3->{ $sc3p }->{ used } = 1;
		}
	    }
        }
    }
}

# Adjust the count,  If $ref is given, the count for reference is also adjusted.
sub adjCnt {
    my ($vref, $tv, $ref) = @_;
    $vref->{ cnt } += $tv->{ cnt };
    $vref->{ extracnt } += $tv->{ cnt };
    $vref->{ hicnt } += $tv->{ hicnt } ? $tv->{ hicnt } : 0;
    $vref->{ locnt } += $tv->{ locnt } ? $tv->{ locnt } : 0;
    $vref->{ pmean } += $tv->{ pmean };
    $vref->{ qmean } += $tv->{ qmean };
    $vref->{ Qmean } += $tv->{ Qmean };
    $vref->{ "+" } += $tv->{ "+" } ? $tv->{ "+" } : 0;
    $vref->{ "-" } += $tv->{ "-" } ? $tv->{ "-" } : 0;
    return unless($ref);
    $ref->{ cnt } -= $tv->{ cnt };
    $ref->{ hicnt } -= $tv->{ hicnt } ? $tv->{ hicnt } : 0;
    $ref->{ locnt } -= $tv->{ locnt } ? $tv->{ locnt } : 0;
    $ref->{ pmean } -= $tv->{ pmean };
    $ref->{ qmean } -= $tv->{ qmean };
    $ref->{ Qmean } -= $tv->{ Qmean };
    $ref->{ "+" } -= $tv->{ "+" } ? $tv->{ "+" } : 0;
    $ref->{ "-" } -= $tv->{ "-" } ? $tv->{ "-" } : 0;
    foreach my $k (qw(cnt hicnt locnt pmean qmean Qmean + -)) {
        $ref->{ $k } = 0 if ( $ref->{ $k } && $ref->{ $k } < 0 );
    }
}

sub findMM3 {
    my ($REF, $p, $seq, $len, $sclip3) = @_;
    my $LONGMM = 3;
    my @mm = (); # mismatches, mismatch positions, 5 or 3 ends
    my $n = 0;
    my $mn = 0;
    my $mcnt = 0;
    my $str = "";
    my $sc3p = 0;
    $n++ while( $REF->{ $p+$n } eq substr($seq, $n, 1) );
    $sc3p = $p + $n;
    while( $REF->{ $p+$n } ne substr($seq, $n, 1) && $mcnt <= $LONGMM && $n < length($seq)) {
        $str .= substr($seq, $n, 1);
	push(@mm, [$str, $sc3p, 5]);
	$n++; $mcnt++;
    }
    # Adject clipping position if only one mismatch
    if ( length($str) == 1 ) {
        $n++ && $mn++ while( $REF->{ $p+$n } eq substr($seq, $n, 1) );
	$sc3p = $p + $n if ( $mn > 1 );
	$sclip3->{ $sc3p }->{ used } = 1 if ( $sclip3->{ $sc3p } && $mn > 1 && $len >= 4);
    }
    return (\@mm, $sc3p);
}

sub findMM5 {
    my ($REF, $p, $seq, $len, $sclip5) = @_;
    my $LONGMM = 3;
    my @mm = (); # mismatches, mismatch positions, 5 or 3 ends
    my $n = 0;
    my $mn = 0;
    my $mcnt = 0;
    my $str = "";
    my $sc5p = 0;
    while( $REF->{ $p-$n } ne substr($seq, -1-$n, 1) && $mcnt < $LONGMM ) {
        $str = substr($seq, -1-$n, 1) . $str;
	push(@mm, [$str, $p-$n, 3]);
	$n++; $mcnt++;
    }
    $sc5p = $p + 1;
    # Adject clipping position if only one mismatch
    if ( length($str) == 1 ) {
        $n++ && $mn++ while( $REF->{ $p-$n } eq substr($seq, -1-$n, 1) );
	$sc5p = $p - $n if ( $mn > 1 );
	$sclip5->{ $sc5p }->{ used } = 1 if ( $sclip5->{ $sc5p } && $mn > 1 && $len >= 4);
    }
    return (\@mm, $sc5p);
}

sub realignins {
    my ($hash, $ins, $cov, $sclip5, $sclip3, $REF, $chr) = @_;
    while(my($p, $iv) = each %$ins) {
        while(my($vn, $icnt) = each %$iv) {
	    #next unless( $icnt >= $MINR );
	    my $vref = $hash->{ $p }->{ I}->{ $vn };
	    my $ins = $1 if ( $vn =~ /^\+([ATGC]+)/ );
	    next unless($ins);
	    my $extra = ($vn =~ /&([ATGC]+)/) ? $1 : "";
	    my $wupseq = join( "", (map { $REF->{ $_ }; } (($p - 100 - length($vn)+1) .. $p))) . $vn; # 5prime flanking seq
	    $wupseq =~ s/\+//; $wupseq =~ s/&//;
	    my $sanpseq = $vn . join( "", (map { $REF->{ $_ }; } (($p + length($extra)+1) .. ($p + length($vn) + 100)))); # 3prime flanking seq
	    $sanpseq =~ s/^\+//; $sanpseq =~ s/&//;
	    my ($mm3, $sc3p) = findMM3($REF, $p+1, $sanpseq, length($ins), $sclip3); # mismatches, mismatch positions, 5 or 3 ends
	    my ($mm5, $sc5p) = findMM5($REF, $p+length($extra), $wupseq, length($ins), $sclip5);
	    my @mm = (@$mm3, @$mm5);
	    #use Object; print STDERR "$sc3p $sc5p\n", Object::Perl(\@mm);
	    for(my $mi = 0; $mi < @mm; $mi++) {
	        my ($mm, $mp, $me) = @{$mm[$mi]};
		substr($mm, 1, 0) = "&" if (length($mm) > 1);
		next unless( $hash->{ $mp } );
		next unless( $hash->{ $mp }->{ $mm } );
		#print STDERR "InDel Realign: $p $mm $mp $me $vn\n";# $tv->{ pmean }/$tv->{ cnt }, "\t", $tv->{ cnt }, "\t$icnt\t", $vn, "\n";
		my $tv = $hash->{ $mp }->{ $mm };
		#print STDERR "InDel Realign: $p $mm $mp $me ", $tv->{ pmean }/$tv->{ cnt }, "\t", $tv->{ cnt }, "\t$icnt\t", $vn, "\n";
		next unless( $tv->{ cnt } );
		next if( $tv->{ qmean }/$tv->{ cnt } < $GOODQ );
		#next if ( $tv->{ pmean }/$tv->{ cnt } > int($dellen/2) + 2 ); #$opt_k;
		next if ( $tv->{ pmean }/$tv->{ cnt } > 4 ); #$opt_k;
		next unless( $tv->{ cnt } < $icnt );
		# Adjust ref cnt so that AF won't > 1
		if ( $mp > $p && $me == 3 ) {
		    $cov->{ $p } += $tv->{ cnt };
		}

		my $ref = ($mp > $p && $me == 5) ? ($hash->{$p}->{ $REF->{$p} } ? $hash->{$p}->{ $REF->{$p} } : "") : "";
		adjCnt($vref, $tv);
		#use Object; print STDERR "A: $mm $mp $me", Object::Perl($ref), "\n";
		#delete $hash->{ $mp }->{ $mm };
		#rmCnt($hash->{ $mp }->{ $mm }, $hash->{ $mp }->{ $mm });
	    }

	    #next if ( length($ins) < 4 ); # soft-clipping only happens when insertion is at least 4 bp
	    #print STDERR "$sc3p $sc5p $icnt\n";
	    if ( $sclip5->{ $sc5p } && (! $sclip5->{ $sc5p }->{ used }) ) {
		my $tv = $sclip5->{ $sc5p };
		my $seq = findconseq( $tv );
		#use Object; print STDERR Object::Perl($sclip5->{ $sc5p });
		#print STDERR $seq, "\t$sc5p, $p\t$tv->{cnt}\t", "$wupseq\n";
		if ( $seq && ismatch($seq, $wupseq, -1) ) {
		#print STDERR "5: $sc5p used\n";
		    $cov->{ $p } += $tv->{ cnt } if ( $sc5p > $p );
		    adjCnt($vref, $tv);
		    $sclip5->{ $sc5p }->{ used } = 1;
		}
	    }
	    if ( $sclip3->{ $sc3p } && (! $sclip3->{ $sc3p }->{ used }) ) {
		my $tv = $sclip3->{ $sc3p };
		my $seq = findconseq( $tv );
		#print STDERR "3: $sample $sc3p $seq $tv->{ cnt } used\n";
		#print STDERR $seq, "\t$sc3p, $p\t$tv->{cnt}\t", findbp($seq, $sc3p + $dellen, $REF, 1, 1), "\n";
		if ( $seq && ismatch($seq, $sanpseq, 1) ) {
		    $cov->{ $p } += $tv->{ cnt } if ( $sc3p <= $p );
		    my $ref = $sc3p <= $p ? "" : $hash->{$p}->{ $REF->{$p} };
		    adjCnt($vref, $tv, $ref);
		    $sclip3->{ $sc3p }->{ used } = 1;
		}
	    }
	}
    }
}

sub ismatch {
    my ($seq1, $seq2, $dir) = @_;
    my ($mm, $n) = (0, 0);
    for(my $n = 0; $n < length($seq1); $n++) {
        $mm++ if ( substr($seq1, $n, 1) ne substr($seq2, $dir*$n - ($dir == -1 ? 1 : 0), 1) );
    }
    return $mm <= 2 ? 1 : 0;
}

sub strandBias {
    my ($fwd, $rev) = @_;
    if ( $fwd + $rev <= 10 ) {
	return $fwd*$rev > 0 ? 2 : 0;
    }
    return ($fwd/($fwd+$rev) >= $BIAS && $rev/($fwd+$rev) >= $BIAS && $fwd >= $MINB && $rev >= $MINB) ? 2 : 1;
}

#FCB02N4ACXX:3:2206:20108:2526#GATGGTTC  163     chr3    38181981        50      79M188N11M      =       38182275        667     TGAAGTTGTGTGTGTCTGACCGCGATGTCCTGCCTGGCACCTGTGTCTGGTCTATTGCTAGTGAGCTCATCGTAAAGAGGTGCCGCCGGG \YY`c`\ZQPJ`e`b]e_Sbabc[^Ybfaega_^cafhR[U^ee[ec][R\Z\__ZZbZ\_\`Z`d^`Zb]bBBBBBBBBBBBBBBBBBB AS:i:-8 XN:i:0  XM:i:2  XO:i:0  XG:i:0  NM:i:2  MD:Z:72A16A0    YT:Z:UU XS:A:+  NH:i:1  RG:Z:15
sub USAGE {
    print STDERR <<USAGE;
    $0 [-n name_reg] [-b bam] [-c chr] [-S start] [-E end] [-s seg_starts] [-e seg_ends] [-x #_nu] [-g gene] [-f freq] [-r #_reads] [-B #_reads] region_info

    The program will calculate candidate variance for a given region(s) in an indexed BAM file. The default
    input is IGV's one or more entries in refGene.txt, but can be any regions in 1-based end-inclusive coordinates.

    -H Print this help page
    -h Print a header row decribing columns
    -z Indicate whether zero-based coordinates, as IGV does (and BED). Affects a given BED file, not option R below.
    -v VCF format output
    -p Do pileup regardless of frequency
    -C Indicate the chromosome names are just numbers, such as 1, 2, not chr1, chr2 (DEPRECATED, uses chr names from given BED or region)
    -D Debug mode.  Will print some error messages and append full genotype at the end.
    -M Similar to -D, but will append individual quality and position data instead of mean
    -3 Indicate to move deletions to 3-prime if alternative alignment can be achieved.
    -F Indicate to whether to filter duplicate, low quality, and secondary alignment reads
    -a distance:cov
       Indicate it's amplicon based calling.  Reads don't map to the amplicon will be skipped.  A read pair is considered belonging
       the amplicon is the edge is less than distance bp to the amplicon, and overlap is at least cov.  Default: 5:0.95
    -k Indel extension
       Indicate the number of bp to rescue forcely aligned reads in deletions and insertions to better represent frequency.  Use with caution.
    -G Genome fasta
       The the reference fasta. Should be indexed (.fai). Defaults to: /ngs/reference_data/genomes/Hsapiens/hg19/seq/hg19.fa
    -R Region
       The region of interest. In the format of chr:start-end, in 1-based end-inclusive coordinates. 
       If end is omitted, then a single position.  No BED is needed.
    -d delimiter
       The delimiter for split region_info, default to tab "\t"
    -n regular_expression
       The regular expression to extract sample name from bam filenames.  Default to: /([^\/\._]+?)_[^\/]*.bam/
    -N string
       The sample name to be used directly.  Will overwrite -n
    -b string
       The indexed BAM file
    -c INT
       The column for chr
    -S INT
       The column for region start, e.g. gene start
    -E INT
       The column for region end, e.g. gene end
    -s INT
       The column for segment starts in the region, e.g. exon starts
    -e INT
       The column for segment ends in the region, e.g. exon ends
    -g INT
       The column for gene name
    -x INT
       The number of nucleotide to extend for each segment, default: 0
    -f double
       The threshold for allele frequency, default: 0.05 or 5%
    -r minimum reads
       The minimum # of variance reads, default 2
    -B INT
       The minimum # of reads to determine strand bias, default 2
    -Q INT
       If set, reads with mapping quality less than INT will be filtered and ignored
    -q INT
       The phred score for a base to be considered a good call.  Default: 25 (for Illumina)
       For PGM, set it to ~15, as PGM tends to under estimate base quality.
    -m INT
       If set, reads with mismatches more than INT will be filtered and ignored.  Gaps are not counted as mismatches.  
       Valid only for bowtie2/TopHat or BWA aln followed by sampe.  BWA mem currently doesn't have such SAM tag
    -T INT
       Trim bases after [INT] bases in the reads
    -X INT
       Extension of bp to look for mismatches after insersion or deletion.  Default to 1 bp, or only calls when they're next to each other.
    -P number
       The read position filter.  If the mean variants position is less that specified, it's considered false positive.  Default: 5
    -Z double
       For downsampling fraction. .g. 0.7 means roughly 70% downsampling.  Default: No downsampling.  Use with caution.  The
       downsampling will be random and non-reproducible.
    -o Qratio
       The Qratio of (good_quality_reads)/(bad_quality_reads+0.5).  The quality is defined by -q option.  Default: 1.5
    -O MapQ
       The reads should have at least mean MapQ to be considered a valid variant.  Default: no filtering
    -V freq
       The lowest frequency in normal sample allowed for a putative somatic mutations.  Default to 0.03
    -L Used for command line pipe, such as "echo chr:pos:gene | checkVar.pl -L".  Will automatically set "-d : -p -c 1 -S 2 -E 2 -g 3"
USAGE
   exit(0);
}

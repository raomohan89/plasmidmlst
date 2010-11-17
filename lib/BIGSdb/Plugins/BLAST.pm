#BLAST.pm - BLAST plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::BLAST;
use strict;
use base qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use List::MoreUtils qw(any);
use BIGSdb::Page 'SEQ_METHODS';

sub get_attributes {
	my %att = (
		name        => 'BLAST',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'BLAST a query sequence against selected isolate data',
		category    => 'Genome',
		buttontext  => 'BLAST',
		menutext    => 'BLAST',
		module      => 'BLAST',
		version     => '1.0.0',
		dbtype      => 'isolates',
		section     => 'analysis',
		order       => 32,
		system_flag => 'BLAST'
	);
	return \%att;
}

sub get_plugin_javascript {
	my $buffer = << "END";
function listbox_selectall(listID, isSelect) {
	var listbox = document.getElementById(listID);
	for(var count=0; count < listbox.options.length; count++) {
		listbox.options[count].selected = isSelect;
	}
}

END
	return $buffer;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $view   = $self->{'system'}->{'view'};
	my $qry =
	  "SELECT DISTINCT $view.id,$view.$self->{'system'}->{'labelfield'} FROM sequence_bin LEFT JOIN $view ON $view.id=sequence_bin.isolate_id ORDER BY $view.id";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute $qry; $@");
	}
	my @ids;
	my %labels;
	while ( my ( $id, $isolate ) = $sql->fetchrow_array ) {
		push @ids, $id;
		$labels{$id} = "$id) $isolate";
	}
	print "<h1>BLAST</h1>\n";
	if ( !@ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There are no sequences in the sequence bin.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"queryform\">\n";
	print "<p>Please select the required isolate ids to BLAST against (use ctrl or shift to make 
	  multiple selections) and paste in your query sequence.  Nucleotide or peptide sequences can be queried.</p>\n";
	print $q->start_form;
	print
"<table style=\"border-collapse:separate; border-spacing:1px\"><tr><th>Isolates</th><th>Parameters</th><th>Paste sequence</th></tr>\n";
	print "<tr><td style=\"text-align:center\">\n";
	print $q->scrolling_list(
		-name     => 'isolate_id',
		-id       => 'isolate_id',
		-values   => \@ids,
		-labels   => \%labels,
		-size     => 12,
		-multiple => 'true'
	);
	print
"<br /><input type=\"button\" onclick='listbox_selectall(\"isolate_id\",true)' value=\"All\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print
"<input type=\"button\" onclick='listbox_selectall(\"isolate_id\",false)' value=\"None\" style=\"margin-top:1em\" class=\"smallbutton\" />\n";
	print "</td><td style=\"text-align:center; vertical-align:top\">\n";
	print "<table><tr><td style=\"text-align:right\">BLASTN word size: </td><td style=\"text-align:left\">\n";
	print $q->popup_menu(
		-name    => 'word_size',
		-values  => [qw(7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28)],
		-default => 11
	);
	print
" <a class=\"tooltip\" title=\"BLASTN word size - This is the length of an exact match required to initiate an extension. Larger values increase speed at the expense of sensitivity.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</td></tr>\n";
	print "<tr><td style=\"text-align:right\">Hits per isolate: </td><td style=\"text-align:left\">\n";
	print $q->popup_menu( -name => 'hits', -values => [qw(1 2 3 4 5 6 7 8 9 10 20 30 40 50)], -default => 1 );
	print "</td></tr>\n";
	print "<tr><td colspan=\"2\" style=\"text-align:left\">";
	print $q->checkbox( -name => 'tblastx', label => 'Use TBLASTX' );
	print
" <a class=\"tooltip\" title=\"TBLASTX - Compares the six-frame translation of your nucleotide query against the six-frame translation of the sequences in the sequence bin.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</td></tr>\n";
	print "<tr><th colspan=\"2\">Restrict included sequences by</th></tr>";
	print "<tr><td style=\"text-align:right\">Sequence method: </td><td style=\"text-align:left\">";
	print $q->popup_menu( -name => 'seq_method', -values => [ '', SEQ_METHODS ] );
	print
" <a class=\"tooltip\" title=\"Sequence method - Only include sequences generated from the selected method.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
	print "</td></tr>\n";
	$sql = $self->{'db'}->prepare("SELECT id,short_description FROM projects ORDER BY short_description");
	my @projects;
	my %project_labels;
	eval { $sql->execute; };
	if ($@) {
		$logger->error("Can't execute $@");
	}	
	while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
		push @projects, $id;
		$project_labels{$id} = $desc;
	}	
	if (@projects) {
		unshift @projects, '';
		print "<tr><td style=\"text-align:right\">Project: </td><td style=\"text-align:left\">";
		print $q->popup_menu( -name => 'project', -values => \@projects, -labels => \%project_labels );
		print
" <a class=\"tooltip\" title=\"Projects - Filter isolate list to only include those belonging to a specific project.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if $self->{'prefs'}->{'tooltips'};
		print "</td></tr>\n";
	}
	$sql = $self->{'db'}->prepare("SELECT id,description FROM experiments ORDER BY description");
	my @experiments;
	undef %labels;
	eval { $sql->execute; };

	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
		push @experiments, $id;
		$labels{$id} = $desc;
	}
	if (@experiments) {
		unshift @experiments, '';
		print "<tr><td style=\"text-align:right\">Experiment: </td><td style=\"text-align:left\">";
		print $q->popup_menu( -name => 'experiment', -values => \@experiments, -labels => \%labels );
		print
" <a class=\"tooltip\" title=\"Experiments - Only include sequences that have been linked to the specified experiment.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if $self->{'prefs'}->{'tooltips'};
		print "</td></tr>\n";
	}
	print "</table>\n</td><td style=\"vertical-align:top\">";
	print $q->textarea( -name => 'sequence', -rows => '10', -cols => '70' );
	print "</td></tr>\n";
	print "<tr><td>";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;name=BLAST\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\" colspan=\"3\">";
	print $q->submit( -name => 'submit', -label => 'Submit', -class => 'submit' );
	print "</td></tr>";
	print "</table>\n";

	foreach (qw (db page name)) {
		print $q->hidden($_);
	}
	print $q->end_form;
	print "</div>\n";
	return if !( $q->param('submit') && $q->param('sequence') );
	@ids = $q->param('isolate_id');
	if ( !@ids ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You must select one or more isolates.</p></div>\n";
		return;
	}
	my $seq = $q->param('sequence');
	print "<div class=\"box\" id=\"resultstable\">\n";
	my $header_buffer = "<table class=\"resultstable\">\n";
	my $labelfield    = $self->{'system'}->{'labelfield'};
	( my $display_label = ucfirst($labelfield) ) =~ tr/_/ /;
	$header_buffer .=
"<tr><th>Isolate id</th><th>$display_label</th><th>% identity</th><th>Alignment length</th><th>Mismatches</th><th>Gaps</th><th>Seqbin id</th><th>Start</th><th>End</th><th>Orientation</th><th>E-value</th><th>Bit score</th></tr>\n";
	my $first        = 1;
	my $some_results = 0;
	$sql = $self->{'db'}->prepare("SELECT $labelfield FROM $self->{'system'}->{'view'} WHERE id=?");
	my $td = 1;
	my $temp = BIGSdb::Utils::get_random();
	my $out_file = "$temp.txt";
	my $out_file_flanking = "$temp\_flanking.txt";
	open (my $fh_output,'>',"$self->{'config'}->{'tmp_dir'}/$out_file") or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file for writing");
	open (my $fh_output_flanking,'>',"$self->{'config'}->{'tmp_dir'}/$out_file_flanking") or $logger->error("Can't open temp file $self->{'config'}->{'tmp_dir'}/$out_file_flanking for writing");

	foreach (@ids) {
		my $matches = $self->_blast( $_, \$seq );
		next if ref $matches ne 'ARRAY' || !@$matches;
		print $header_buffer if $first;
		$some_results = 1;
		eval { $sql->execute($_); };
		if ($@) {
			$logger->error("Can't execute $@");
		}
		my ($label)     = $sql->fetchrow_array;
		my $rows        = @$matches;
		my $first_match = 1;
		foreach my $match (@$matches) {
			if ($first_match) {
				print
"<tr class=\"td$td\"><td rowspan=\"$rows\" style=\"vertical-align:top\">$_</td><td rowspan=\"$rows\" style=\" vertical-align:top\">$label</td>";
			} else {
				print "<tr class=\"td$td\">";
			}
			foreach my $attribute (qw(identity alignment mismatches gaps seqbin_id start end)) {
				print "<td>$match->{$attribute}";
				if ( $attribute eq 'end' ) {
					print
" <a target=\"_blank\" class=\"extract_tooltip\" href=\"$self->{'script_name'}?db=$self->{'instance'}&amp;page=extractedSequence&amp;translate=1&amp;no_highlight=1&amp;seqbin_id=$match->{'seqbin_id'}&amp;start=$match->{'start'}&amp;end=$match->{'end'}&amp;reverse=$match->{'reverse'}\">extract&nbsp;&rarr;</a>";
				}
				print "</td>";
			}
			print "<td style=\"font-size:2em\">" . ( $match->{'reverse'} ? '&larr;' : '&rarr;' ) . "</td>";
			foreach my $attribute (qw(e_value bit_score)) {
				print "<td>$match->{$attribute}</td>";
			}
			print "</tr>\n";
			$first_match = 0;
			my $flanking = $self->{'prefs'}->{'flanking'};
			my $start = $match->{'start'};
			my $end = $match->{'end'};
			my $length   = abs( $end - $start + 1 );
			my $qry =
"SELECT substring(sequence from $start for $length) AS seq,substring(sequence from ($start-$flanking) for $flanking) AS upstream,substring(sequence from ($end+1) for $flanking) AS downstream FROM sequence_bin WHERE id=?";
			my $seq_ref = $self->{'datastore'}->run_simple_query_hashref( $qry, $match->{'seqbin_id'} );
			$seq_ref->{'seq'}        = BIGSdb::Utils::reverse_complement( $seq_ref->{'seq'} )        if $match->{'reverse'};
			$seq_ref->{'upstream'}   = BIGSdb::Utils::reverse_complement( $seq_ref->{'upstream'} )   if $match->{'reverse'};
			$seq_ref->{'downstream'} = BIGSdb::Utils::reverse_complement( $seq_ref->{'downstream'} ) if $match->{'reverse'};
			print $fh_output ">$_|$label|$match->{'seqbin_id'}|$start\n";
			print $fh_output_flanking ">$_|$label|$match->{'seqbin_id'}|$start\n";
			print $fh_output BIGSdb::Utils::break_line($seq_ref->{'seq'},60) . "\n";
			if ($match->{'reverse'}){
				print $fh_output_flanking BIGSdb::Utils::break_line($seq_ref->{'downstream'} . $seq_ref->{'seq'} . $seq_ref->{'upstream'},60) . "\n";
			} else {
				print $fh_output_flanking BIGSdb::Utils::break_line($seq_ref->{'upstream'} . $seq_ref->{'seq'} . $seq_ref->{'downstream'},60) . "\n";
			}
		}
		$td = $td == 1 ? 2 : 1;
		$first = 0;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			if ( $self->{'mod_perl_request'}->connection->aborted ) {
				return;
			}
		}
	}
	if ($some_results) {
		print "</table>\n";
		print "<p style=\"margin-top:1em\">Download <a href=\"/tmp/$out_file\">FASTA</a> | <a href=\"/tmp/$out_file_flanking\">FASTA with flanking</a>";
		print
" <a class=\"tooltip\" title=\"Flanking sequence - You can change the amount of flanking sequence exported by selecting the appropriate length in the options page.\">&nbsp;<i>i</i>&nbsp;</a>"
	  if $self->{'prefs'}->{'tooltips'};
		
		print "</p>\n";
	} else {
		print "<p>No matches found.</p>\n";
	}
	close $fh_output;
	close $fh_output_flanking;
	print "</div>\n";
}

sub _blast {
	my ( $self, $isolate_id, $seq_ref ) = @_;
	my $seq_type = BIGSdb::Utils::sequence_type($$seq_ref);
	$$seq_ref =~ s/\s//g;
	my $program;
	if ( $seq_type eq 'DNA' ) {
		$program = $self->{'cgi'}->param('tblastx') ? 'tblastx' : 'blastn';
	} else {
		$program = 'tblastn';
	}
	my $file_prefix    = BIGSdb::Utils::get_random();
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_file.txt";
	my $temp_outfile   = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_outfile.txt";
	my $temp_queryfile = "$self->{'config'}->{'secure_tmp_dir'}/$file_prefix\_query.txt";
	my $outfile_url    = "$file_prefix\_outfile.txt";

	#create query FASTA file
	open( my $queryfile_fh, '>', $temp_queryfile ) or $logger->error("Can't open temp file $temp_queryfile for writing");
	print $queryfile_fh ">query\n$$seq_ref\n";
	close $queryfile_fh;

	#create isolate FASTA database
	my $qry = "SELECT DISTINCT sequence_bin.id,sequence FROM sequence_bin LEFT JOIN experiment_sequences ON sequence_bin.id=seqbin_id LEFT JOIN project_members ON sequence_bin.isolate_id = project_members.isolate_id WHERE sequence_bin.isolate_id=?";
	my @criteria = ($isolate_id);
	my $method   = $self->{'cgi'}->param('seq_method');
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= " AND method=?";
		push @criteria, $method;
	}
	my $project = $self->{'cgi'}->param('project');
		if ($project) {
			if ( !BIGSdb::Utils::is_int($project) ) {
				$logger->error("Invalid project $project");
				return;
			}	
			$qry .= " AND project_id=?";
			push @criteria, $project;		
		}
	my $experiment = $self->{'cgi'}->param('experiment');
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$qry .= " AND experiment_id=?";
		push @criteria, $experiment;
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@criteria); };
	if ($@) {
		$logger->error("Can't execute $qry $@");
	}
	open( my $fastafile_fh, '>', $temp_fastafile ) or $logger->error("Can't open temp file $temp_fastafile for writing");
	while ( my ( $id, $seq ) = $sql->fetchrow_array ) {
		print $fastafile_fh ">$id\n$seq\n";
	}
	close $fastafile_fh;
	return if -z $temp_fastafile;
	system("$self->{'config'}->{'blast_path'}/formatdb -i $temp_fastafile -p F -o T");
	my $blastn_word_size = $1 if $self->{'cgi'}->param('word_size') =~ /(\d+)/;
	my $hits             = $1 if $self->{'cgi'}->param('hits')      =~ /(\d+)/;
	my $word_size = $program eq 'blastn' ? ( $blastn_word_size || 11 ) : 0;
	$hits = 1 if !$hits;
	$logger->error($isolate_id);
	system(
"$self->{'config'}->{'blast_path'}/blastall -b $hits -p $program -W $word_size -d $temp_fastafile -i $temp_queryfile -o $temp_outfile -m8 -F F 2> /dev/null"
	);
	my $matches = $self->_parse_blast( $outfile_url, $hits );

	#clean up
	system "rm -f $self->{'config'}->{'secure_tmp_dir'}/*$file_prefix*";
	return $matches;
}

sub _parse_blast {
	my ( $self, $blast_file, $hits ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return \$; );
	my @matches;
	my $rows;
	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		my $match;
		$match->{'seqbin_id'} = $record[1];
		$match->{'identity'}  = $record[2];
		$match->{'alignment'} = $record[3];
		$match->{'mismatches'}      = $record[4];
		$match->{'gaps'} = $record[5];
		$match->{'reverse'}   = 1
		  if ( ( $record[8] > $record[9] && $record[7] > $record[6] ) || ( $record[8] < $record[9] && $record[7] < $record[6] ) );

		if ( $record[8] < $record[9] ) {
			$match->{'start'} = $record[8];
			$match->{'end'}   = $record[9];
		} else {
			$match->{'start'} = $record[9];
			$match->{'end'}   = $record[8];
		}
		$match->{'e_value'}   = $record[10];
		$match->{'bit_score'} = $record[11];
		push @matches, $match;
		$rows++;
		last if $rows == $hits;
	}
	close $blast_fh;
	return \@matches;
}
1;

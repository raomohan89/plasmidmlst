#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
package BIGSdb::CurateAddSeqbinPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage BIGSdb::SeqbinPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Bio::DB::GenBank;
use Try::Tiny;
use BIGSdb::Constants qw(SEQ_METHODS :interface :limits);

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Upload sequences</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status(
			{ message => q(This function can only be called for an isolate database.), navbar => 1 } );
		return;
	} elsif ( !$self->can_modify_table('sequence_bin') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to upload sequences to the database.),
				navbar  => 1
			}
		);
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload;
		return;
	}
	$self->print_seqbin_warnings( scalar $q->param('isolate_id') );
	if ( $q->param('data') ) {
		$self->_check_data;
	} elsif ( $q->param('fasta_upload') ) {
		my $upload_file = $self->_upload_fasta_file;
		my $full_path   = "$self->{'config'}->{'secure_tmp_dir'}/$upload_file";
		if ( -e $full_path ) {
			my $seq_ref = BIGSdb::Utils::slurp($full_path);
			unlink $full_path;
			$self->_check_data($seq_ref);
		}
	} elsif ( $q->param('accession') ) {
		try {
			my $acc_seq_ref = $self->_upload_accession;
			if ($acc_seq_ref) {
				$self->_check_data($acc_seq_ref);
			}
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				$logger->debug($_);
				if ( $_ eq 'INVALID_ACCESSION' ) {
					$self->print_bad_status( { message => q(Accession is invalid.) } );
				} elsif ( $_ eq 'NO_DATA' ) {
					$self->print_bad_status(
						{ message => q(The accession is valid but it contains no sequence data.) } );
				}
				$self->_print_interface;
			} else {
				$logger->logdie($_);
			}
		};
	} else {
		my $icon = $self->get_form_icon( 'sequence_bin', 'plus' );
		say $icon;
		$self->_print_interface;
	}
	return;
}

sub print_seqbin_warnings {
	my ( $self, $isolate_id ) = @_;
	if ( $isolate_id && BIGSdb::Utils::is_int($isolate_id) ) {
		my $seqbin = $self->{'datastore'}->run_query(
			'SELECT * FROM seqbin_stats WHERE isolate_id=? AND isolate_id IN '
			  . "(SELECT id FROM $self->{'system'}->{'view'})",
			$isolate_id,
			{ fetch => 'row_hashref' }
		);
		my $remote_clause =
		  ( $self->{'system'}->{'remote_contigs'} // q() ) eq 'yes'
		  ? q( Reported total contig length may not be accurate if these refer to remotely hosted contigs which have )
		  . q(not yet been validated.)
		  : q();
		if ($seqbin) {
			say q(<div class="box" id="warning"><p>Sequences have already been uploaded for this isolate.</p>)
			  . qq(<ul><li>Contigs: $seqbin->{'contigs'}</li><li>Total length: $seqbin->{'total_length'} bp</li></ul>)
			  . qq(<p>Please make sure that you intend to add new sequences for this isolate.$remote_clause</p></div>);
		}
	}
	return;
}

sub _print_interface {
	my ( $self, $options ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform"><div class="scrollable">);
	say q(<p>This page allows you to upload sequence data for a specified isolate record in FASTA format.</p>)
	  . q(<p>If an isolate id is chosen, then all sequences will be associated with that isolate. Alternatively, )
	  . q(the isolate id, or any other isolate table field that uniquely defines the isolate, can be named in the )
	  . q(identifier rows of the FASTA file.  This allows data for multiple isolates to be uploaded.</p>);
	say q(<p><em>Please note that you can reach this page for a specific isolate by )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query">querying isolates</a> )
	  . q(and then clicking 'Upload' within the isolate table.</em></p>);
	say $q->start_form( -onMouseMove => 'enable_identifier_field()' );
	my ( $users, $user_names ) = $self->{'datastore'}->get_users( { blank_message => 'Select sender ...' } );
	say q(<p>Please fill in the following fields - required fields are marked with an exclamation mark (!).</p>);
	say q(<fieldset style="float:left"><legend>Paste in sequences in FASTA format:</legend>);
	say $q->hidden($_) foreach qw (page db);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80 );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Attributes</legend><ul>);
	my $sender;
	my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");

	if ( $q->param('isolate_id') && !$options->{'error'} ) {
		say q(<li><label class="parameter">isolate id: !</label>);
		my $isolate_id = $q->param('isolate_id');
		my $isolate_name;
		if ( BIGSdb::Utils::is_int($isolate_id) ) {
			$isolate_name =
			  $self->{'datastore'}
			  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
				$isolate_id );
			$isolate_name //= 'Invalid isolate';
			$sender =
			  $self->{'datastore'}
			  ->run_query( "SELECT sender FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
		} else {
			$isolate_name = 'Invalid isolate';
		}
		say qq{<span id="isolate_id">$isolate_id) $isolate_name</span>};
		say $q->hidden( 'isolate_id', $isolate_id );
	} elsif ( $isolate_count > MAX_ISOLATES_DROPDOWN ) {
		say q(<li><label for="isolate_id" class="parameter">isolate id: !</label>);
		say $self->textfield( -name => 'isolate_id', id => 'isolate_id', required => 'required', type => 'number' );
	} else {
		say q(<li><label for="isolate_id" class="parameter">isolate id: !</label>);
		my $id_arrayref =
		  $self->{'datastore'}
		  ->run_query( "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} ORDER BY id",
			undef, { fetch => 'all_arrayref' } );
		my @ids = (0);
		my %labels;
		$labels{'0'} = 'Read identifier from FASTA';
		foreach (@$id_arrayref) {
			push @ids, $_->[0];
			$labels{ $_->[0] } = "$_->[0]) $_->[1]";
		}
		say $self->popup_menu( -name => 'isolate_id', -id => 'isolate_id', -values => \@ids, -labels => \%labels );
		say q(</li><li><label for="identifier_field" class="parameter">identifier field: !</label>);
		my $fields = $self->{'xmlHandler'}->get_field_list;
		say $q->popup_menu( -name => 'identifier_field', -id => 'identifier_field', -values => $fields );
	}
	say q(</li><li><label for="sender" class="parameter">sender: !</label>);
	say $self->popup_menu(
		-name     => 'sender',
		-id       => 'sender',
		-values   => [ '', @$users ],
		-labels   => $user_names,
		-required => 'required',
		-default  => $sender
	);
	say q(</li><li><label for="method" class="parameter">method: </label>);
	my $method_labels = { '' => ' ' };
	say $q->popup_menu( -name => 'method', -id => 'method', -values => [ '', SEQ_METHODS ], -labels => $method_labels );
	say q(</li><li><label for="run_id" class="parameter">run id: </label>);
	say $q->textfield( -name => 'run_id', -id => 'run_id', -size => 32 );
	say q(</li><li><label for="assembly_id" class="parameter">assembly id: </label>);
	say $q->textfield( -name => 'assembly_id', -id => 'assembly_id', -size => 32 );
	my $seq_attributes =
	  $self->{'datastore'}->run_query( 'SELECT key,type,description FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );

	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			( my $label = $attribute->{'key'} ) =~ s/_/ /;
			say qq(<li><label for="$attribute->{'key'}" class="parameter">$label:</label>\n);
			say $q->textfield( -name => $attribute->{'key'}, -id => $attribute->{'key'} );
			if ( $attribute->{'description'} ) {
				say $self->get_tooltip(qq($attribute->{'key'} - $attribute->{'description'}.));
			}
		}
	}
	say q(</li></ul></fieldset><fieldset style="float:left"><legend>Options</legend>);
	say q(<ul><li>);
	say $q->checkbox( -name => 'size_filter', -label => q(Don't insert sequences shorter than ) );
	say $q->popup_menu( -name => 'size', -values => [qw(25 50 100 200 300 400 500 1000)], -default => 250 );
	say q( bps.</li>);
	my @experiments = ('');
	my $exp_data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,description FROM experiments ORDER BY description', undef, { fetch => 'all_arrayref' } );
	my $exp_labels = { '' => ' ' };

	foreach my $data (@$exp_data) {
		push @experiments, $data->[0];
		$exp_labels->{ $data->[0] } = $data->[1];
	}
	if ( @experiments > 1 ) {
		say q(<li><label for="experiment" class="parameter">Link to experiment: </label>);
		say $q->popup_menu(
			-name   => 'experiment',
			-id     => 'experiment',
			-values => \@experiments,
			-labels => $exp_labels
		);
		say q(</li>);
	}
	say q(</ul></fieldset>);
	say qq(<fieldset style="float:left">\n<legend>Alternatively upload FASTA file</legend>);
	say q(Select FASTA file:<br />);
	say $q->filefield( -name => 'fasta_upload', -id => 'fasta_upload' );
	say q(</fieldset>);
	if ( !$self->{'config'}->{'intranet'} ) {
		say q(<fieldset style="float:left"><legend>or enter Genbank accession</legend>);
		say $q->textfield( -name => 'accession' );
		say q(</fieldset>);
	}
	my %args =
	  defined $q->param('isolate_id') ? ( isolate_id => scalar $q->param('isolate_id') ) : ();
	$self->print_action_fieldset( \%args );
	say $q->end_form;
	$self->print_navigation_bar;
	say q(</div></div>);
	return;
}

sub _check_data {
	my ( $self, $passed_seq_ref ) = @_;
	my $q        = $self->{'cgi'};
	my $continue = 1;
	if ( !$q->param('isolate_id') ) {
		$self->print_bad_status( { message => q(Isolate id is required.) } );
		$continue = 0;
	} elsif (
		$q->param('isolate_id')
		&& (
			!BIGSdb::Utils::is_int( scalar $q->param('isolate_id') )
			|| !$self->{'datastore'}->run_query(
				"SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
				scalar $q->param('isolate_id')
			)
		)
	  )
	{
		$self->print_bad_status( { message => q(Isolate id must be an integer and exist in the isolate table.) } );
		$continue = 0;
	} elsif ( !$q->param('sender')
		|| !BIGSdb::Utils::is_int( scalar $q->param('sender') )
		|| !$self->{'datastore'}
		->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=?)', scalar $q->param('sender') ) )
	{
		$self->print_bad_status( { message => q(Sender is required and must exist in the users table.) } );
		$continue = 0;
	}
	my $seq_attributes = $self->{'datastore'}->run_query( 'SELECT key,type FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my @att_problems;
	foreach my $attribute (@$seq_attributes) {
		my $value = $q->param( $attribute->{'key'} );
		next if !defined $value || $value eq '';
		if ( $attribute->{'type'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
			push @att_problems, "$attribute->{'key'} must be an integer.";
		} elsif ( $attribute->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
			push @att_problems, "$attribute->{'key'} must be a floating point value.";
		} elsif ( $attribute->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value) ) {
			push @att_problems, "$attribute->{'key'} must be a valid date in yyyy-mm-dd format.";
		}
	}
	if (@att_problems) {
		local $" = '<br />';
		$self->print_bad_status( { message => qq(@att_problems) } );
		$continue = 0;
	}
	my $seq_ref;
	if ($continue) {
		try {
			my $data = $q->param('data');
			$seq_ref = BIGSdb::Utils::read_fasta( $passed_seq_ref // \$data, { keep_comments => 1 } );
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				if ( $_ =~ /DNA/x ) {
					my $header;
					if ( $_ =~ /DNA\ -\ (.*)$/x ) {
						$header = $1;
					}
					$self->print_bad_status(
						{ message => qq(FASTA data '$header' contains non-valid nucleotide characters.) } );
					$continue = 0;
				} else {
					$self->print_bad_status( { message => q(Sequence data is not in valid FASTA format.) } );
					$continue = 0;
				}
			} else {
				$logger->logdie($_);
			}
		};
	}
	if ( !$continue ) {
		$self->_print_interface( { error => 1 } );
		return;
	}
	if ( $q->param('isolate_id') ) {
		$self->_check_records_single_isolate( $seq_ref, $seq_attributes );
	} else {
		$self->_check_records_with_identifiers( $seq_ref, $seq_attributes );
	}
	return;
}

sub _check_records_single_isolate {
	my ( $self, $seq_ref, $seq_attributes ) = @_;
	my $q              = $self->{'cgi'};
	my $checked_buffer = [];
	my $td             = 1;
	my $min_size       = 0;
	if ( $q->param('size_filter') && BIGSdb::Utils::is_int( scalar $q->param('size') ) ) {
		$min_size = $q->param('size');
	}
	my $buffer;
	foreach ( sort { $a cmp $b } keys %$seq_ref ) {
		my $length = length( $seq_ref->{$_} );
		next if $length < $min_size;
		push @$checked_buffer, ">$_";
		push @$checked_buffer, $seq_ref->{$_};
		my ( $designation, $comments );
		if ( $_ =~ /(\S*)\s+(.*)/x ) {
			( $designation, $comments ) = ( $1, $2 );
		} else {
			$designation = $_;
		}
		$buffer .= qq(<tr class="td$td"><td>$designation</td>);
		$buffer .= qq(<td>$length</td>);
		$buffer .= defined $comments ? qq(<td>$comments</td>) : q(<td></td>);
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	if ($buffer) {
		say q(<div class="box" id="resultstable">);
		say q(<fieldset style="float:left"><legend>The following sequences will be entered.</legend>);
		say q(<table class="resultstable"><tr><th>Original designation</th>)
		  . q(<th>Sequence length</th><th>Comments</th></tr>);
		say $buffer if $buffer;
		say q(</table></fieldset>);
		my $num;
		my $min = 0;
		my $max = 0;
		my ( $mean, $total );
		my @lengths;

		foreach ( values %$seq_ref ) {
			my $length = length $_;
			next if $length < $min_size;
			$min = $length if !$min || $length < $min;
			$max = $length if $length > $max;
			$total += $length;
			push @lengths, $length;
			$num++;
		}
		@lengths = sort { $b <=> $a } @lengths;
		$mean = int $total / $num if $num;
		my $n_stats = BIGSdb::Utils::get_N_stats( $total, \@lengths );
		say q(<fieldset style="float:left"><legend>Summary</legend>);
		say $self->get_list_block(
			[
				{ title => 'Number of contigs',       data => BIGSdb::Utils::commify($num) },
				{ title => 'Minimum length',          data => BIGSdb::Utils::commify($min) },
				{ title => 'Maximum length',          data => BIGSdb::Utils::commify($max) },
				{ title => 'Total length',            data => BIGSdb::Utils::commify($total) },
				{ title => 'Mean length',             data => BIGSdb::Utils::commify($mean) },
				{ title => 'N50 contig number',       data => BIGSdb::Utils::commify( $n_stats->{'N50'} ) },
				{ title => 'N50 contig length (L50)', data => BIGSdb::Utils::commify( $n_stats->{'L50'} ) },
				{ title => 'N90 contig number',       data => BIGSdb::Utils::commify( $n_stats->{'N90'} ) },
				{ title => 'N90 contig length (L50)', data => BIGSdb::Utils::commify( $n_stats->{'L90'} ) },
				{ title => 'N95 contig number',       data => BIGSdb::Utils::commify( $n_stats->{'N95'} ) },
				{ title => 'N95 contig length (L50)', data => BIGSdb::Utils::commify( $n_stats->{'L95'} ) },
			],
			{ width => 15 }
		);
		say q(</fieldset>);
		say $q->start_form;
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Upload' } );
		my $filename = $self->make_temp_file(@$checked_buffer);
		$q->param( 'checked_buffer', $filename );
		say $q->hidden($_)
		  foreach qw (db page checked_buffer isolate_id sender method run_id assembly_id comments experiment);
		say $q->hidden( $_->{'key'} ) foreach (@$seq_attributes);
		say $q->end_form;
	} else {
		$self->print_bad_status( { message => q(No valid sequences to upload.), navbar => 1 } );
	}
	say q(</div>);
	return;
}

sub _check_records_with_identifiers {
	my ( $self, $seq_ref, $seq_attributes ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="resultstable">);
	say q(<p>The following sequences will be entered.  Any problems are highlighted.</p>);
	say q(<fieldset style="float:left"><legend>Contigs</legend>);
	say q(<table class="resultstable"><tr><th>BIGSdb id</th>);
	my $id_field = $q->param('identifier_field');
	say qq(<th>Identifier field ($id_field)</th>) if $id_field ne 'id';
	say q(<th>Sequence length</th><th>Comments</th><th>Status</th></tr>);
	my $attributes   = $self->{'xmlHandler'}->get_field_attributes($id_field);
	my $td           = 1;
	my $allow_upload = 0;
	my $min_size     = 0;

	if ( $q->param('size_filter') && BIGSdb::Utils::is_int( scalar $q->param('size') ) ) {
		$min_size = $q->param('size_filter') && $q->param('size');
	}
	my $checked_buffer = [];
	foreach my $identifier ( sort { $a cmp $b } keys %$seq_ref ) {
		my $length = length( $seq_ref->{$identifier} );
		my ( $designation, $comments, $status );
		if ( $identifier =~ /(\S*)\s+(.*)/x ) {
			( $designation, $comments ) = ( $1, $2 );
		} else {
			$designation = $identifier;
		}
		$comments ||= '';
		my $identifier_field_html = $id_field eq 'id' ? q() : qq(<td>$identifier</td>);
		my $id_error;
		if ( $attributes->{'type'} eq 'int' && !BIGSdb::Utils::is_int($identifier) ) {
			$status = q(Identifier field must be an integer);
			$designation = $id_field eq 'id' ? $identifier : q(-);
			say qq(<tr class="td$td"><td class="statusbad">$designation</td>);
			say $identifier_field_html if $identifier_field_html;
			say qq(<td>$length</td><td>$comments</td><td class="statusbad">$status</td></tr>);
		} else {
			my $ids = $self->{'datastore'}->run_query( "SELECT id FROM $self->{'system'}->{'view'} WHERE $id_field=?",
				$identifier, { fetch => 'col_arrayref', cache => 'CurateBatchAddSeqbinPage::check_data::read_id' } );
			if ( !@$ids ) {
				$id_error = q(No matching record);
				$designation = $id_field eq 'id' ? $identifier : '-';
			} elsif ( @$ids > 1 ) {
				$id_error    = scalar @$ids . q( matching records - can't uniquely identify isolate);
				$designation = '-';
			} else {
				($designation) = @$ids;
			}
			if ( $length < $min_size ) {
				$status = q(Sequence too short - will be ignored);
				say qq(<tr class="td$td"><td>$designation</td>$identifier_field_html)
				  . qq(<td class="statusbad">$length</td><td>$comments</td><td class="statusbad">$status</td></tr>);
			} elsif ($id_error) {
				say qq(<tr class="td$td"><td>$designation</td>$identifier_field_html<td>$length</td>)
				  . qq(<td>$comments</td><td class="statusbad">$id_error</td></tr>);
			} else {
				push @$checked_buffer, qq(>$designation);
				push @$checked_buffer, $seq_ref->{$identifier};
				$status = q(Will upload);
				say qq(<tr class="td$td"><td>$designation</td>);
				say $identifier_field_html if $identifier_field_html;
				say qq(<td>$length</td><td>$comments</td><td class="statusgood">$status</td></tr>);
				$allow_upload = 1;
			}
		}
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table>);
	say q(</fieldset>);
	if ($allow_upload) {
		say $q->start_form;
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Upload' } );
		my $filename = $self->make_temp_file(@$checked_buffer);
		$q->param( checked_buffer => $filename );
		say $q->hidden($_) foreach qw (db page checked_buffer isolate_id identifier_field
		  sender method run_id assembly_id comments);
		say $q->hidden( $_->{'key'} ) foreach (@$seq_attributes);
		say $q->end_form;
	} else {
		say q(<fieldset style="float:left"><legend>Status</legend><p>Nothing to upload.</p></fieldset>);
		say q(<div style="clear:both"></div>);
	}
	say q(</div>);
	return;
}

sub _upload {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $dir      = $self->{'config'}->{'secure_tmp_dir'};
	my $tmp_file = $dir . '/' . $q->param('checked_buffer');
	my $fasta_ref;
	if ( -e $tmp_file ) {
		$fasta_ref = BIGSdb::Utils::slurp($tmp_file);
	} else {
		$self->print_bad_status(
			{
				message   => q(Checked temporary file is no longer available. Please start again.),
				navbar    => 1,
				back_page => 'addSeqbin'
			}
		);
		return;
	}
	my $seq_ref;
	my $continue = 1;
	try {
		$seq_ref = BIGSdb::Utils::read_fasta( $fasta_ref, { keep_comments => 1 } );
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Data') ) {
			$logger->error('Invalid FASTA file');
			$continue = 0;
		} else {
			$logger->logdie($_);
		}
	};
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+\.txt)$/x ) {
		$logger->info("Deleting temp file $tmp_file");
		unlink $1;
	} else {
		$logger->error("Can't delete temp file $tmp_file");
	}
	if ( !$continue ) {
		$self->print_bad_status(
			{
				message   => q(Unable to upload sequences. Please try again.),
				navbar    => 1,
				back_page => 'addSeqbin'
			}
		);
		return;
	}
	my $qry = 'INSERT INTO sequence_bin (isolate_id,sequence,method,run_id,assembly_id,original_designation,'
	  . 'comments,sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?,?,?)';
	my $sql = $self->{'db'}->prepare($qry);
	$qry = 'INSERT INTO experiment_sequences (experiment_id,seqbin_id,curator,datestamp) VALUES (?,?,?,?)';
	my $sql_experiment = $self->{'db'}->prepare($qry);
	my $experiment     = BIGSdb::Utils::is_int( scalar $q->param('experiment') ) ? $q->param('experiment') : undef;
	my $curator        = $self->get_curator_id;
	my $sender         = $q->param('sender');
	my $seq_attributes = $self->{'datastore'}->run_query( 'SELECT key,type FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my @attribute_sql;

	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			if ( $q->param( $attribute->{'key'} ) ) {
				( my $value = $q->param( $attribute->{'key'} ) ) =~ s/'/\\'/gx;
				$qry = q(INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) VALUES )
				  . qq((?,'$attribute->{'key'}',E'$value',$curator,'now'));
				push @attribute_sql, $self->{'db'}->prepare($qry);
			}
		}
	}
	eval {
		foreach ( keys %$seq_ref ) {
			my ( $designation, $comments );
			if ( $_ =~ /(\S*)\s+(.*)/x ) {
				( $designation, $comments ) = ( $1, $2 );
			} else {
				$designation = $_;
			}
			my $isolate_id = $q->param('isolate_id') ? $q->param('isolate_id') : $designation;
			undef $designation if !$q->param('isolate_id') || $designation eq q();
			foreach my $field (qw(method run_id assembly_id)) {
				$q->delete($field) if defined $q->param($field) && $q->param($field) eq q();
			}
			my @values = (
				$isolate_id, $seq_ref->{$_},
				$q->param('method')      // undef,
				$q->param('run_id')      // undef,
				$q->param('assembly_id') // undef,
				$designation, $comments, $sender, $curator, 'now', 'now'
			);
			$sql->execute(@values);
			my $id = $self->{'db'}->last_insert_id( undef, undef, 'sequence_bin', 'id' );
			$sql_experiment->execute( $experiment, $id, $curator, 'now' ) if $experiment;
			$_->execute($id) foreach @attribute_sql;
		}
	};
	if ($@) {
		local $" = ', ';
		my $message = 'Failed! - transaction cancelled - no records have been touched.';
		my $detail;
		if ( $@ =~ /duplicate/x && $@ =~ /unique/x ) {
			$detail = q(Data entry would have resulted in records with either duplicate ids or )
			  . q(another unique field with duplicate values.);
		} else {
			$detail = qq(Error message: $@);
		}
		$self->print_bad_status( { message => $message, detail => $detail } );
		$self->{'db'}->rollback;
		return;
	} else {
		$self->{'db'}->commit;
		$self->print_good_status(
			{
				message  => q(Sequences uploaded.),
				navbar   => 1,
				more_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=addSeqbin&amp;)
				  . qq(sender=$sender")
			}
		);
	}
	return;
}

sub _upload_fasta_file {
	my ($self)   = @_;
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_upload.fas";
	my $buffer;
	open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload('fasta_upload');
	binmode $fh2;
	binmode $fh;
	read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
	print $fh $buffer;
	close $fh;
	return "$temp\_upload.fas";
}

sub _upload_accession {
	my ($self)    = @_;
	my $accession = $self->{'cgi'}->param('accession');
	my $seq_db    = Bio::DB::GenBank->new;
	$seq_db->retrieval_type('tempfile');    #prevent forking resulting in duplicate error message on fail.
	my $sequence;
	try {
		my $seq_obj = $seq_db->get_Seq_by_acc($accession);
		$sequence = $seq_obj->seq;
	}
	catch {
		my $err = shift;
		$logger->debug($err);
		BIGSdb::Exception::Data->throw('INVALID_ACCESSION');
	};
	if ( !length($sequence) ) {
		BIGSdb::Exception::Data->throw('NO_DATA');
	}
	return \">$accession\n$sequence";
}

sub get_javascript {
	my $buffer = << "END";

function enable_identifier_field(){
	var element = document.getElementById('isolate_id');
	if (element.value == 0){
		document.getElementById('identifier_field').disabled=false;
	} else {
		document.getElementById('identifier_field').disabled=true;
	}
}
	
END
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new sequences - $desc";
}
1;

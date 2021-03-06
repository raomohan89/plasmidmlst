#Written by Keith Jolley
#Copyright (c) 2014-2019, University of Oxford
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
package BIGSdb::REST::Routes::Profiles;
use strict;
use warnings;
use 5.010;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Profile routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/schemes/:scheme_id/profiles"             => sub { _get_profiles() };
		get "$dir/db/:db/schemes/:scheme_id/profiles_csv"         => sub { _get_profiles_csv() };
		get "$dir/db/:db/schemes/:scheme_id/profiles/:profile_id" => sub { _get_profile() };
	}
	return;
}

sub _get_profiles {
	my $self = setting('self');
	if ( request->accept =~ /(tsv|csv)/x ) {
		_get_profiles_csv();
	}
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $allowed_filters = [qw(added_after added_on updated_after updated_on)];
	my $set_id          = $self->get_set_id;
	$self->check_scheme( $scheme_id, { pk => 1 } );
	my $subdir           = setting('subdir');
	my $scheme_info      = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $qry = $self->add_filters( "SELECT COUNT(*),max(datestamp) FROM $scheme_warehouse", $allowed_filters );
	my ( $profile_count, $last_updated ) = $self->{'datastore'}->run_query($qry);
	my $page_values = $self->get_page_values($profile_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
	$qry = $self->add_filters( "SELECT $scheme_info->{'primary_key'} FROM $scheme_warehouse", $allowed_filters );
	$qry .= ' ORDER BY '
	  . (
		$pk_info->{'type'} eq 'integer'
		? "CAST($scheme_info->{'primary_key'} AS int)"
		: $scheme_info->{'primary_key'}
	  );
	$qry .= " LIMIT $self->{'page_size'} OFFSET $offset" if !param('return_all');
	my $profiles = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	my $values = { records => int($profile_count) };
	$values->{'last_updated'} = $last_updated if defined $last_updated;
	my $path = $self->get_full_path( "$subdir/db/$db/schemes/$scheme_id/profiles", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $profile_links = [];

	foreach my $profile_id (@$profiles) {
		push @$profile_links, request->uri_for("$subdir/db/$db/schemes/$scheme_id/profiles/$profile_id");
	}
	$values->{'profiles'} = $profile_links;
	return $values;
}

sub _get_profiles_csv {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id ) = @{$params}{qw(db scheme_id)};
	my $allowed_filters = [qw(added_after added_on updated_after updated_on)];
	$self->check_scheme( $scheme_id, { pk => 1 } );
	my $set_id        = $self->get_set_id;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my @heading       = ( $scheme_info->{'primary_key'} );
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @fields        = ( $scheme_info->{'primary_key'}, 'profile' );
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	my @order;

	foreach my $locus (@$loci) {
		my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		push @heading, $header_value;
		push @order,   $locus_indices->{$locus};
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $scheme_info->{'primary_key'};
		push @heading, $field;
		push @fields,  $field;
	}
	local $" = "\t";
	my $buffer = "@heading\n";
	local $" = ',';
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $pk_info          = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $qry              = $self->add_filters( "SELECT @fields FROM $scheme_warehouse", $allowed_filters );
	$qry .= ' ORDER BY ' . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	my $data = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref' } );

	if ( !@$data ) {
		send_error( "No profiles for scheme $scheme_id are defined.", 404 );
	}
	local $" = "\t";
	{
		no warnings 'uninitialized';    #scheme field values may be undefined
		foreach my $definition (@$data) {
			my $pk      = shift @$definition;
			my $profile = shift @$definition;
			$buffer .= qq($pk\t@$profile[@order]\t@$definition\n);
		}
	}
	send_file( \$buffer, content_type => 'text/plain; charset=UTF-8' );
	return;
}

sub _get_profile {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $scheme_id, $profile_id ) = @{$params}{qw(db scheme_id profile_id)};
	$self->check_scheme($scheme_id);
	my $page        = ( BIGSdb::Utils::is_int( param('page') ) && param('page') > 0 ) ? param('page') : 1;
	my $set_id      = $self->get_set_id;
	my $subdir      = setting('subdir');
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info->{'primary_key'} ) {
		send_error( "Scheme $scheme_id does not have a primary key field.", 400 );
	}
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $profile =
	  $self->{'datastore'}->run_query( "SELECT * FROM $scheme_warehouse WHERE $scheme_info->{'primary_key'}=?",
		$profile_id, { fetch => 'row_hashref' } );
	if ( !$profile ) {
		send_error( "Profile $scheme_info->{'primary_key'}-$profile_id does not exist.", 404 );
	}
	my $values        = {};
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $allele_links  = [];
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	foreach my $locus (@$loci) {
		my $cleaned_locus = $self->clean_locus($locus);
		my $allele_id     = $profile->{'profile'}->[ $locus_indices->{$locus} ];
		push @$allele_links, request->uri_for("$subdir/db/$db/loci/$cleaned_locus/alleles/$allele_id");
	}
	$values->{'alleles'} = $allele_links;
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$fields) {
		next if !defined $profile->{ lc($field) };
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $field_info->{'type'} eq 'integer' ) {
			$values->{$field} = int( $profile->{ lc($field) } );
		} else {
			$values->{$field} = $profile->{ lc($field) };
		}
	}
	my $profile_info = $self->{'datastore'}->run_query(
		'SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?',
		[ $scheme_id, $profile_id ],
		{ fetch => 'row_hashref' }
	);
	foreach my $attribute (qw(sender curator date_entered datestamp)) {
		if ( $attribute eq 'sender' || $attribute eq 'curator' ) {

			#Don't link to user 0 (setup user)
			$values->{$attribute} =
			  request->uri_for("$subdir/db/$db/users/$profile_info->{$attribute}")
			  if $profile_info->{$attribute};
		} else {
			$values->{$attribute} = $profile_info->{$attribute};
		}
	}
	return $values;
}
1;

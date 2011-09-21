#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::Curate;
use strict;
use warnings;
use base qw(BIGSdb::Application);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub db_connect {
	my ($self) = @_;
	my %att = (
		'dbase_name' => $self->{'system'}->{'db'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'password'},
		'writable'   => 1
	);
	try {
		$self->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		my $logger = get_logger('BIGSdb.Application_Initiate');
		$logger->fatal("Can not connect to database '$self->{'system'}->{'db'}'");
	};
	return;
}

sub print_page {
	my ( $self, $dbase_config_dir ) = @_;
	my %classes = (
		'index'              => 'CurateIndexPage',
		'add'                => 'CurateAddPage',
		'delete'             => 'CurateDeletePage',
		'deleteAll'          => 'CurateDeleteAllPage',
		'update'             => 'CurateUpdatePage',
		'isolateAdd'         => 'CurateIsolateAddPage',
		'isolateQuery'       => 'QueryPage',
		'browse'             => 'BrowsePage',
		'listQuery'          => 'ListQueryPage',
		'isolateDelete'      => 'CurateIsolateDeletePage',
		'isolateUpdate'      => 'CurateIsolateUpdatePage',
		'batchIsolateUpdate' => 'CurateBatchIsolateUpdatePage',
		'pubmedQuery'        => 'CuratePubmedQueryPage',
		'batchAdd'           => 'CurateBatchAddPage',
		'batchAddSeqbin'     => 'CurateBatchAddSeqbinPage',
		'tableHeader'        => 'CurateTableHeaderPage',
		'compositeQuery'     => 'CurateCompositeQueryPage',
		'compositeUpdate'    => 'CurateCompositeUpdatePage',
		'alleleUpdate'       => 'CurateAlleleUpdatePage',
		'info'               => 'IsolateInfoPage',
		'pubquery'           => 'PubQueryPage',
		'profileAdd'         => 'CurateProfileAddPage',
		'profileQuery'       => 'QueryPage',
		'profileUpdate'      => 'CurateProfileUpdatePage',
		'profileBatchAdd'    => 'CurateProfileBatchAddPage',
		'tagScan'            => 'CurateTagScanPage',
		'tagUpdate'          => 'CurateTagUpdatePage',
		'databankScan'       => 'CurateDatabankScanPage',
		'renumber'           => 'CurateRenumber',
		'seqbin'             => 'SeqbinPage',
		'embl'               => 'SeqbinToEMBL',
		'configCheck'        => 'ConfigCheckPage',
		'configRepair'		 => 'ConfigRepairPage',
		'changePassword'     => 'ChangePasswordPage',
		'setPassword'        => 'ChangePasswordPage',
		'profileInfo'        => 'ProfileInfoPage',
		'alleleInfo'         => 'AlleleInfoPage',
		'isolateACL'         => 'CurateIsolateACLPage',
		'fieldValues'        => 'FieldHelpPage',
		'tableQuery'         => 'TableQueryPage',
		'extractedSequence'  => 'ExtractedSequencePage',
		'downloadSeqbin'     => 'DownloadSeqbinPage',
		'linkToExperiment'   => 'CurateLinkToExperimentPage',
		'alleleSequence'     => 'AlleleSequencePage',
		'options'            => 'OptionsPage',
		'exportConfig'       => 'CurateExportConfig'
	);
	my %page_attributes = (
		'system'           => $self->{'system'},
		'dbase_config_dir' => $dbase_config_dir,
		'cgi'              => $self->{'cgi'},
		'instance'         => $self->{'instance'},
		'prefs'            => $self->{'prefs'},
		'prefstore'        => $self->{'prefstore'},
		'config'           => $self->{'config'},
		'datastore'        => $self->{'datastore'},
		'db'               => $self->{'db'},
		'xmlHandler'       => $self->{'xmlHandler'},
		'dataConnector'    => $self->{'dataConnector'},
		'mod_perl_request' => $self->{'mod_perl_request'},
		'curate'           => 1
	);
	my $page;
	my $continue = 1;
	my $auth_cookies_ref;
	if ( $self->{'error'} ) {
		$page_attributes{'error'} = $self->{'error'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print;
		return;
	} else {
		( $continue, $auth_cookies_ref ) = $self->authenticate( \%page_attributes );
	}
	return if !$continue;
	if ( $self->{'system'}->{'read_access'} eq 'acl'
		|| ( defined $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' ) )
	{
		$self->initiate_view( \%page_attributes );    #replace current view with one containing only isolates viewable by user
		$page_attributes{'system'} = $self->{'system'};
	}
	my $user_status;
	eval {
		$user_status =
		  $self->{'datastore'}->run_simple_query( "SELECT status FROM users WHERE user_name=?", $page_attributes{'username'} )->[0];
	};
	$logger->error($@) if $@;
	if ( !defined $user_status || ($user_status ne 'admin' && $user_status ne 'curator' )) {
		$page_attributes{'error'} = 'invalidCurator';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
		$page->print;
		return;
	} elsif ( !$self->{'db'} ) {
		$page_attributes{'error'} = 'noConnect';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( !$self->{'prefstore'} ) {
		$page_attributes{'error'} = 'noPrefs';
		$page_attributes{'fatal'} = $self->{'fatal'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( ( $self->{'system'}->{'disable_updates'} && $self->{'system'}->{'disable_updates'} eq 'yes' )
		|| ( $self->{'config'}->{'disable_updates'} && $self->{'config'}->{'disable_updates'} eq 'yes' ) )
	{
		$page_attributes{'error'}   = 'disableUpdates';
		$page_attributes{'message'} = $self->{'config'}->{'disable_update_message'} || $self->{'system'}->{'disable_update_message'};
		$page_attributes{'fatal'}   = $self->{'fatal'};
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	} elsif ( $classes{ $self->{'page'} } ) {
		if ( ref $auth_cookies_ref eq 'ARRAY' ) {
			foreach (@$auth_cookies_ref) {
				push @{ $page_attributes{'cookies'} }, $_;
			}
		}
		$page = "BIGSdb::$classes{$self->{'page'}}"->new(%page_attributes);
	} else {
		$page_attributes{'error'} = 'unknown';
		$page = BIGSdb::ErrorPage->new(%page_attributes);
	}
	$page->print;
	return;
}
1;

#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

BEGIN {
    $ENV{INTERN_BOOKMARK_ENV} ||= 'local';
}

use FindBin;
use lib "$FindBin::Bin/lib", glob "$FindBin::Bin/modules/*/lib";
use Pod::Usage; # for pod2usage()
use Digest::SHA;
use Encode;
use Encode::Locale;
use File::Slurp;
use Intern::Bookmark::Model::Bookmark;
use Intern::Bookmark::Model::Entry;
use Intern::Bookmark::Model::User;
use Intern::Bookmark::Util;

binmode STDOUT, ':encoding(console_out)';

my $CURRENT_USER = Intern::Bookmark::Model::User->new(
    user_id => $ENV{USER},
    name    => $ENV{USER},
);

my %HANDLERS = (
    add    => \&add_bookmark,
    list   => \&list_bookmarks,
    delete => \&delete_bookmark,
);

my $command = shift @ARGV || 'list';

my $handler = $HANDLERS{ $command } or pod2usage;

$handler->(@ARGV);

exit 0;

sub current_user { $CURRENT_USER }

sub add_bookmark {
    my ($url, $comment) = @_;

    die 'url required' unless defined $url;

    my $now = Intern::Bookmark::Util::now;
    my $entry_id = generate_entry_id(url => $url);
    my $entry = Intern::Bookmark::Model::Entry->new(
        entry_id => $entry_id,
        url      => $url,
        created  => datetime_as_string($now),
        updated  => datetime_as_string($now),
    );
    my $bookmark_id = generate_bookmark_id(entry => $entry, user => current_user());
    my $bookmark = Intern::Bookmark::Model::Bookmark->new(
        bookmark_id => $bookmark_id,
        comment     => $comment,
        entry       => $entry,
        user        => current_user(),
        created     => datetime_as_string($now),
        updated     => datetime_as_string($now),
    );
    my $bookmark_ltsv = generate_ltsv_by_hashref($bookmark->as_flatten_hashref);
    File::Slurp::write_file("data/$bookmark_id.ltsv", $bookmark_ltsv);

    print 'Bookmarked ' . $bookmark->entry->url . ' ' . $bookmark->comment . "\n";
}

sub list_bookmarks {
    my $bookmark_files = [ glob 'data/*.ltsv' ];
    my $bookmarks      = [ map { parse_bookmark_ltsv_file($_) } @$bookmark_files ];

    foreach my $bookmark (@$bookmarks) {
        print $bookmark->entry->url . ' ' . $bookmark->comment . "\n";
    }
}

sub delete_bookmark {
    my ($url) = @_;

    die 'url required' unless defined $url;

    my $entry_id = generate_entry_id(url => $url);
    my $entry = Intern::Bookmark::Model::Entry->new(entry_id => $entry_id);
    my $bookmark_id = generate_bookmark_id(entry => $entry, user => current_user());
    unlink "data/$bookmark_id.ltsv" or die "Cannot delete bookmark: $!";
    print "Deleted \n";
}

sub build_entry_by_flatten_hashref {
    my ($hashref) = @_;
    my $entry_hashref = { map {
        ($_ => $hashref->{"entry.$_"})
    } qw(entry_id url title created updated) };
    my $entry = Intern::Bookmark::Model::Entry->new($entry_hashref);
    return $entry;
}

sub build_user_by_flatten_hashref {
    my ($hashref) = @_;
    my $user = build_object_by_flatten_hashref(
        class     => 'Intern::Bookmark::Model::User',
        namespace => 'user',
        fields    => [qw(user_id name)],
        hashref   => $hashref,
    );
    return $user;
}

sub build_bookmark_by_flatten_hashref {
    my ($hashref) = @_;
    my $bookmark = build_object_by_flatten_hashref(
        class     => 'Intern::Bookmark::Model::Bookmark',
        namespace => 'bookmark',
        fields    => [qw(bookmark_id comment created updated)],
        hashref   => $hashref,
    );
    return $bookmark;
}

sub build_object_by_flatten_hashref {
    my (%args) = @_;
    my $class     = $args{class};
    my $namespace = $args{namespace};
    my $hashref   = $args{hashref};
    my $fields    = $args{fields};
    my $raw_hashref = { map {
        ($_ => $hashref->{"$namespace.$_"})
    } @$fields };
    my $blessed = $class->new($raw_hashref);
    return $blessed;
}

sub parse_ltsv {
    my ($record) = @_;
    my $fields = [ split "\t", $record ];
    my $hashref = { map {
        my ($label, $value) = split ':', $_, 2;
        ($label => $value eq '-' ? undef : $value);
    } @$fields };
    return $hashref;
}

sub parse_bookmark_ltsv_file {
    my ($filename) = @_;
    my $record   = File::Slurp::read_file($filename);
    my $hashref  = parse_ltsv($record);
    my $entry    = build_entry_by_flatten_hashref($hashref);
    my $user     = build_user_by_flatten_hashref($hashref);
    my $bookmark = build_bookmark_by_flatten_hashref($hashref);
    $bookmark->entry($entry);
    $bookmark->user($user);
    return $bookmark;
}

sub generate_ltsv_by_hashref {
    my ($hashref) = @_;
    my $fields = [ map { join ':', $_, $hashref->{$_} } keys %$hashref ];
    my $record = join("\t", @$fields) . "\n";
    return $record;
}

sub generate_entry_id {
    my (%args) = @_;
    my $url = $args{url};
    return Digest::SHA::sha1_hex($url);
}

sub generate_bookmark_id {
    my (%args) = @_;
    my $entry = $args{entry};
    my $user  = $args{user};
    return Digest::SHA::sha1_hex(join ':', $entry->entry_id, $user->user_id);
}

sub datetime_as_string {
    my ($dt) = @_;
    return $dt->formatter->format_datetime($dt);
}

__END__

=head1 NAME

bookmark-file.pl - my bookmark

=head1 SYNOPSIS

  bookmark.pl add URL [COMMENT]

  bookmark.pl list

  bookmark.pl delete URL

=

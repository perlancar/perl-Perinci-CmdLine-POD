package Perinci::CmdLine::POD;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

$SPEC{gen_pod_for_pericmd_script} = {
    v => 1.1,
    summary => 'Generate POD for Perinci::CmdLine-based CLI script',
    description => <<'_',

This utility can accept either a path to a <pm:Perinci::CmdLine>-based CLI
script, upon which the arguments to Perinci::CmdLine constructor will be
extracted using a script dumper (<pm:Perinci::CmdLine::Dump>), or a set of
arguments to specify Perinci::CmdLine constructor arguments directly (e.g.
`url`, `summary`, `subcommands`, etc).

_
    args => {
        script => {
            summary => 'Path to script',
            schema => 'filename*',
            tags => ['category:input'],
        },

        url => {
            schema => 'str*',
            tags => ['category:input'],
        },
        program_name => {
            schema => 'str*',
            tags => ['category:input'],
        },
        summary => {
            schema => 'str*',
            tags => ['category:input'],
        },
        subcommands => {
            schema => ['hash*', of=>'hash*'],
            tags => ['category:input'],
        },
        default_subcommand => {
            schema => 'str*',
            tags => ['category:input'],
        },
        per_arg_json => {
            schema => ['bool*', is=>1],
            default => 1,
            tags => ['category:input'],
        },
        per_arg_yaml => {
            schema => ['bool*', is=>1],
            default => 1,
            tags => ['category:input'],
        },
        read_env => {
            schema => ['bool*', is=>1],
            default => 1,
            tags => ['category:input'],
        },
        env_name => {
            schema => 'str*',
            tags => ['category:input'],
        },
        read_config => {
            schema => ['bool*', is=>1],
            default => 1,
            tags => ['category:input'],
        },
        config_filename => {
            schema => ['any*', of=>[
                'str*',
                ['array*', of=>'str*'],
                ['array*', of=>'hash*'],
            ]],
            tags => ['category:input'],
        },
        config_dirs => {
            schema => ['array*', of=>'dirname*'],
            tags => ['category:input'],
        },
    },
    args_rels => {
        req_one => [qw/script url/],
    },
};
sub gen_pod_for_pericmd_script {
    my %args = @_;

    if (defined $args{script}) {
        require Perinci::CmdLine::Dump;
        my $res = Perinci::CmdLine::Dump::dump_
    }
}

1;
# ABSTRACT:

=head1 SYNOPSIS

Please see the included CLI script L<gen-pod-for-pericmd-script>.


=for Pod::Coverage ^(new)$


=head1 SEE ALSO

L<Perinci::CmdLine>

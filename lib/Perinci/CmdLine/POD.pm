package Perinci::CmdLine::POD;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Data::Dmp;
use IPC::System::Options qw(system);
use Proc::ChildError qw(explain_child_error);
use String::ShellQuote;

use Exporter 'import';
our @EXPORT_OK = qw(gen_pod_for_pericmd_script);

our $pa = do {
    require Perinci::Access::Perl;
    Perinci::Access::Perl->new;
};

our %SPEC;

sub _fmt_opt {
    my ($opt, $ospec) = @_;

    my @res;

    my $arg_spec = $ospec->{arg_spec};
    my $is_bool = $arg_spec->{schema} &&
        $arg_spec->{schema}[0] eq 'bool';
    my $show_default = exists($ospec->{default}) &&
        !$is_bool && !$ospec->{main_opt} && !$ospec->{is_alias};

    my $add_sum = '';
    if ($ospec->{is_base64}) {
        $add_sum = " (base64-encoded)";
    } elsif ($ospec->{is_json}) {
        $add_sum = " (JSON-encoded)";
    } elsif ($ospec->{is_yaml}) {
        $add_sum = " (YAML-encoded)";
    }

    $opt =~ s/(?P<name>--?.+?)(?P<val>=(?P<dest>[\w@-]+)|,|\z)/"B<" . $+{name} . ">" . ($+{dest} ? "=I<".$+{dest}.">" : $+{val})/eg;

    push @res, "=item $opt\n\n";

    push @res, "$ospec->{summary}$add_sum.\n\n" if $ospec->{summary};

    push @res, "Default value:\n\n ", dmp($ospec->{default}), "\n\n" if $show_default;

    if ($arg_spec->{schema} && $arg_spec->{schema}[1]{in} && !$ospec->{is_alias}) {
        push @res, "Valid values:\n\n ", dmp($arg_spec->{schema}[1]{in}), "\n\n";
    }

    if ($ospec->{main_opt}) {
        my $main_opt = $ospec->{main_opt};
        $main_opt =~ s/\s*,.+//;
        $main_opt =~ s/=.+//;
        push @res, "See C<$main_opt>.\n\n";
    } else {
        push @res, "$ospec->{description}\n\n" if $ospec->{description};
    }

    if (($ospec->{orig_opt} // '') =~ /\@/) {
        push @res, "Can be specified multiple times.\n\n";
    } elsif (($ospec->{orig_opt} // '') =~ /\%/) {
        push @res, "Each value is a name-value pair, use I<key=value> syntax. Can be specified multiple times.\n\n";
    }

    join "", @res;
}

sub _list_config_params {
    my ($clidocdata, $filter) = @_;

    my $opts = $clidocdata->{opts};
    my %param2opts;
    for (keys %$opts) {
        my $ospec = $opts->{$_};
        next unless $ospec->{common_opt} && $ospec->{common_opt_spec}{is_settable_via_config};
        next if $filter && !$filter->($ospec);
        my $oname = $ospec->{opt_parsed}{opts}[0];
        $oname = length($oname) > 1 ? "--$oname" : "-$oname";
        $param2opts{ $ospec->{common_opt} } = $oname;
    }
    for (keys %$opts) {
        my $ospec = $opts->{$_};
        next unless $ospec->{arg};
        next if $ospec->{main_opt};
        next if $filter && !$filter->($ospec);
        my $oname = $ospec->{opt_parsed}{opts}[0];
        $oname = length($oname) > 1 ? "--$oname" : "-$oname";
        my $confname = $param2opts{$_} ?
            "$ospec->{arg}.arg" : $ospec->{arg};
        $param2opts{$confname} = $oname;
    }
    \%param2opts;
}

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
        common_opts => {
            schema => 'hash*',
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
        choose_all => [qw/url common_opts/],
    },
};
sub gen_pod_for_pericmd_script {
    no warnings 'once';

    my %args = @_;

    my %metas; # key = subcommand name

    my ($cli, $dump_res);
    if (defined $args{script}) {
        require Perinci::CmdLine::Dump;
        my $dump_res = Perinci::CmdLine::Dump::dump_pericmd_script(
            filename => $args{script},
        );
        return $dump_res unless $dump_res->[0] == 200;
        $cli = $dump_res->[2];
        %metas = %{ $dump_res->[3]{'func.pericmd_inline_metas'} }
            if $dump_res->[3]{'func.pericmd_inline_metas'};
    } else {
        require Perinci::CmdLine::Lite;
        $cli = Perinci::CmdLine::Lite->new(
            url                => $args{url},
            program_name       => $args{program_name},
            summary            => $args{summary},
            common_opts        => $args{common_opts},
            subcommands        => $args{subcommands},
            default_subcommand => $args{default_subcommand},
            per_arg_json       => $args{per_arg_json},
            per_arg_yaml       => $args{per_arg_yaml},
            read_env           => $args{read_env},
            env_name           => $args{env_name},
            read_config        => $args{read_config},
            config_filename    => $args{config_filenames},
            config_dirs        => $args{config_dirs},
        );
    }

    local %main::SPEC = %{ $dump_res->[3]{'func.meta'} }
        if $dump_res->[3]{'func.meta'};

    # generate clidocdata(for all subcommands; if there is no subcommand then it
    # is stored in key '')
    my %clidocdata; # key = subcommand name
    my %urls; # key = subcommand name

    {
        require Perinci::Sub::To::CLIDocData;

        my $url = $cli->{url};
        $urls{''} = $url;
        unless ($metas{''}) {
            my $res = $pa->request(meta => $url);
            die "Can't meta $url: $res->[0] - $res->[1]"
                unless $res->[0] == 200;
            $metas{''} = $res->[2];
        }
        my $res = Perinci::Sub::To::CLIDocData::gen_cli_doc_data_from_meta(
            meta => $metas{''},
            meta_is_normalized => 0, # because riap client is specifically set not to normalize
            common_opts  => $cli->{common_opts},
            per_arg_json => $cli->{per_arg_json},
            per_arg_yaml => $cli->{per_arg_yaml},
        );
        die "Can't gen_cli_doc_data_from_meta: $res->[0] - $res->[1]"
            unless $res->[0] == 200;
        $clidocdata{''} = $res->[2];

        if ($cli->{subcommands}) {
            if (ref($cli->{subcommands}) eq 'CODE') {
                die "Script '$args{script}': sorry, coderef 'subcommands' not ".
                    "supported yet";
            }
            for my $sc_name (keys %{ $cli->{subcommands} }) {
                my $sc_spec = $cli->{subcommands}{$sc_name};
                my $url = $sc_spec->{url};
                $urls{$sc_name} = $url;
                unless ($metas{$sc_name}) {
                    my $res = $pa->request(meta => $url);
                    die "Can't meta $url (subcommand $sc_name): $res->[0] - $res->[1]"
                        unless $res->[0] == 200;
                    $metas{$sc_name} = $res->[2];
                }
                $res = Perinci::Sub::To::CLIDocData::gen_cli_doc_data_from_meta(
                    meta => $metas{$sc_name},
                    meta_is_normalized => 0, # because riap client is specifically set not to normalize
                    common_opts => $cli->{common_opts},
                    per_arg_json => $cli->{per_arg_json},
                    per_arg_yaml => $cli->{per_arg_yaml},
                );
                die "Can't gen_cli_doc_data_from_meta (subcommand $sc_name): $res->[0] - $res->[1]"
                    unless $res->[0] == 200;
                $clidocdata{$sc_name} = $res->[2];
            }
        }
    }

    my $resmeta = {
        'func.sections' => [],
    };
    my @pod;

    my $prog = $args{program_name} // $cli->{program_name};
    if (!$prog && defined $args{script}) {
        $prog = $args{script};
        $prog =~ s!.+/!!;
    }
    my $summary = $args{summary} // $cli->{summary} //
        $metas{''}{summary} // '(no summary)';

    # section: NAME
    {
        my @sectpod;
        push @sectpod, "$prog - $summary\n\n";
        push @{ $resmeta->{'func.sections'} }, {name=>'NAME', content=>join("", @sectpod), ignore=>1};
        push @pod, "=head1 NAME\n\n", @sectpod;
    }

    my $version = $metas{''}{entity_v} // '(dev)';

    # section: VERSION
    {
        my @sectpod;
        push @sectpod, "$version\n\n";
        $resmeta->{'func.section.version'} = \@sectpod;
        push @{ $resmeta->{'func.sections'} }, {name=>'VERSION', content=>join("", @sectpod), ignore=>1};
        push @pod, "=head1 VERSION\n\n", @sectpod;
    }

    # section: SYNOPSIS
    {
        my @sectpod;
        push @sectpod, "Usage:\n\n";
        if ($cli->{subcommands}) {
            for my $sc_name (sort keys %clidocdata) {
                next unless length $sc_name;
                my $usage = $clidocdata{$sc_name}->{usage_line};
                $usage =~ s/\[\[prog\]\]/$prog $sc_name/;
                push @sectpod, " % $usage\n";
            }
            push @sectpod, "\n";
        } else {
            my $usage = $clidocdata{''}->{usage_line};
            $usage =~ s/\[\[prog\]\]/$prog/;
            push @sectpod, " % $usage\n\n";
        }

        my @examples;
        for my $sc_name (sort keys %clidocdata) {
            next unless length $sc_name;
            my $i = 1;
            for my $eg (@{ $clidocdata{$sc_name}{examples} }) {
                # add pointer to subcommand, we need it later to show result
                $eg->{_sc_name} = $sc_name;
                $eg->{_i} = $i;
                push @examples, $eg;
                $i++;
            }
        }
        if (@examples) {
            push @sectpod, "Examples:\n\n";
            for my $eg (@examples) {
                my $url = $urls{ $eg->{_sc_name} };
                my $meta = $metas{ $eg->{_sc_name} };
                push @sectpod, "$eg->{summary}:\n\n" if $eg->{summary};
                my $cmdline = $eg->{cmdline};
                $cmdline =~ s/\[\[prog\]\]/$prog/;
                push @sectpod, " % $cmdline\n";

                my $show_result;
              SHOW_RESULT:
                {
                    my $fres;
                    last unless $eg->{example_spec}{'x.doc.show_result'} // 1;

                    if ($eg->{example_spec}{src}) {
                        if ($eg->{example_spec}{src_plang} =~ /\A(bash)\z/) {
                            # execute script and get its output
                            if (defined $args{script}) {
                                my $cmdline = $eg->{cmdline};
                                $cmdline =~ s/\[\[prog\]\]/shell_quote($^X, "-Ilib", $args{script})/e;
                                system(
                                    {shell => 0, capture_stdout => \$fres},
                                    "bash", "-c", $cmdline);
                                if ($?) {
                                    die sprintf("Example #%d (subcommand %s): cmdline %s: failed: %s", $eg->{_i}, $eg->{_sc_name}, $cmdline, explain_child_error());
                                }
                            }
                            if (my $max_lines = $eg->{example_spec}{'x.doc.max_result_lines'}) {
                                my @lines = split /^/, $fres;
                                if (@lines > $max_lines) {
                                    my $n = int($max_lines/2);
                                    splice @lines, $n, (@lines - $max_lines + 1), "...\n";
                                    $fres = join("", @lines);
                                }
                            }
                            #$self->log_debug(["fres: %s", $fres]);
                        } else {
                            warn sprintf("Example #%d (subcommand %s) has src with unsupported src_plang ($eg->{srg_plang}), skipped showing result", $eg->{_i}, $eg->{_sc_name});
                            last SHOW_RESULT;
                        }
                    } else {
                        my $res;
                        if (exists $eg->{example_spec}{result}) {
                            $res = $eg->{example_spec}{result};
                        } else {
                            my %extra;
                            if ($eg->{example_spec}{argv}) {
                                $extra{argv} = $eg->{example_spec}{argv};
                            } elsif ($eg->{example_spec}{args}) {
                                $extra{args} = $eg->{example_spec}{args};
                            } else {
                                #$self->log_debug(["Example #%d (subcommand %s) doesn't provide args/argv, skipped showing result", $eg->{_i}, $eg->{_sc_name}]);
                                last SHOW_RESULT;
                            }
                            $res = $pa->request(call => $url, \%extra);
                        }
                        my $format = $res->[3]{'cmdline.default_format'} // $cli->{default_format} // 'text-pretty';
                        require Perinci::Result::Format::Lite;
                        $fres = Perinci::Result::Format::Lite::format($res, $format);
                    }

                    $fres =~ s/^/ /gm;
                    push @sectpod, $fres;
                    push @sectpod, "\n";
                    $show_result = 1;
                } # SHOW_RESULT

                unless ($show_result) {
                    push @sectpod, "\n";
                }
            }
        }

        push @{ $resmeta->{'func.sections'} }, {name=>'SYNOPSIS', content=>join("", @sectpod), ignore=>1};
        push @pod, "=head1 SYNOPSIS\n\n", @sectpod;
    }

    # section: DESCRIPTION
    {
        last unless $metas{''}{description};

        require Markdown::To::POD;

        my @sectpod;
        push @sectpod,
            Markdown::To::POD::markdown_to_pod($metas{''}{description});
        push @sectpod, "\n\n";

        push @{ $resmeta->{'func.sections'} }, {name=>'DESCRIPTION', content=>join("", @sectpod), ignore=>1};
        push @pod, "=head1 DESCRIPTION\n\n", @sectpod;
    }

    # section: SUBCOMMANDS
    {
        last unless $cli->{subcommands};

        my @sectpod;
        my %sc_spec_refs; # key=ref address, val=first subcommand name
        for my $sc_name (sort keys %clidocdata) {
            next unless length $sc_name;
            my $sc_spec = $cli->{subcommands}{$sc_name};

            my $spec_same_as;
            if (defined $sc_spec_refs{"$sc_spec"}) {
                $spec_same_as = $sc_spec_refs{"$sc_spec"};
            } else {
                $sc_spec_refs{"$sc_spec"} = $sc_name;
            }

            my $meta = $metas{$sc_name};
            push @sectpod, "=head2 B<$sc_name>\n\n";

            # assumed alias because spec has been seen before
            if ($spec_same_as) {
                push @sectpod, "Alias for C<$spec_same_as>.\n\n";
                next;
            }

            my $summary = $sc_spec->{summary} // $meta->{summary};
            push @sectpod, "$summary.\n\n" if $summary;

            next if $sc_spec->{is_alias};

            my $description = $sc_spec->{description} // $meta->{description};
            if ($description) {
                push @sectpod,
                    Markdown::To::POD::markdown_to_pod($description);
                push @sectpod, "\n\n";
            }
        }

        push @{ $resmeta->{'func.sections'} }, {name=>'SUBCOMMANDS', content=>join("", @sectpod), ignore=>1};
        push @pod, "=head1 SUBCOMMANDS\n\n", @sectpod;
    }

    my @sc_names = grep { length } sort keys %clidocdata;

    # section: OPTIONS
    {
        my @sectpod;
        push @sectpod, "C<*> marks required options.\n\n";

        if ($cli->{subcommands}) {

            use experimental 'smartmatch';

            # currently categorize by subcommand instead of category

            my $check_common_arg = sub {
                my ($opts, $name) = @_;
                return 1 if 'common' ~~ @{ $opts->{$name}{tags} // []};
                return 1 if !$opts->{$name}{arg};
                0;
            };

            # first display options tagged with 'common' as well as common
            # option (non-function argument option, like --format or
            # --log-level). these are supposed to be the same across
            # subcommands.
            {
                my $opts = $clidocdata{ $sc_names[0] }{opts};
                my @opts = sort {
                    (my $a_without_dash = $a) =~ s/^-+//;
                    (my $b_without_dash = $b) =~ s/^-+//;
                    lc($a) cmp lc($b);
                } grep {$check_common_arg->($opts, $_)} keys %$opts;
                push @sectpod, "=head2 Common options\n\n";
                push @sectpod, "=over\n\n";
                for (@opts) {
                    push @sectpod, _fmt_opt($_, $opts->{$_});
                }
                push @sectpod, "=back\n\n";
            }

            # display each subcommand's options (without the options tagged as
            # 'common')
            my %sc_spec_refs;
            for my $sc_name (@sc_names) {
                my $sc_spec = $cli->{subcommands}{$sc_name};

                my $spec_same_as;
                if (defined $sc_spec_refs{"$sc_spec"}) {
                    $spec_same_as = $sc_spec_refs{"$sc_spec"};
                } else {
                    $sc_spec_refs{"$sc_spec"} = $sc_name;
                }
                next if defined $spec_same_as;
                next if $sc_spec->{is_alias};

                my $opts = $clidocdata{$sc_name}{opts};
                my @opts = sort {
                    (my $a_without_dash = $a) =~ s/^-+//;
                    (my $b_without_dash = $b) =~ s/^-+//;
                    lc($a) cmp lc($b);
                } grep {!$check_common_arg->($opts, $_)} keys %$opts;
                next unless @opts;
                push @sectpod, "=head2 Options for subcommand $sc_name\n\n";
                push @sectpod, "=over\n\n";
                for (@opts) {
                    push @sectpod, _fmt_opt($_, $opts->{$_});
                }
                push @sectpod, "=back\n\n";
            }
        } else {
            my $opts = $clidocdata{''}{opts};
            # find all the categories
            my %options_by_cat; # val=[options...]
            for my $optkey (keys %$opts) {
                for my $cat (@{ $opts->{$optkey}{categories} }) {
                    push @{ $options_by_cat{$cat} }, $optkey;
                }
            }
            my $cats_spec = $clidocdata{''}{option_categories};
            for my $cat (sort {
                ($cats_spec->{$a}{order} // 50) <=> ($cats_spec->{$b}{order} // 50)
                    || $a cmp $b }
                             keys %options_by_cat) {
                push @sectpod, "=head2 $cat\n\n"
                    unless keys(%options_by_cat) == 1;

                my @opts = sort {
                    (my $a_without_dash = $a) =~ s/^-+//;
                    (my $b_without_dash = $b) =~ s/^-+//;
                    lc($a) cmp lc($b);
                } @{ $options_by_cat{$cat} };
                push @sectpod, "=over\n\n";
                for (@opts) {
                    push @sectpod, _fmt_opt($_, $opts->{$_});
                }
                push @sectpod, "=back\n\n";
            }
        }

        push @{ $resmeta->{'func.sections'} }, {name=>'OPTIONS', content=>join("", @sectpod)};
        push @pod, "=head1 OPTIONS\n\n", @sectpod;
    }

    # section: ENVIRONMENT
    {
        # workaround because currently the dumped object does not contain all
        # attributes in the hash (Moo/Mo issue?), we need to access the
        # attribute accessor method first to get them recorded in the hash. this
        # will be fixed in the dump module in the future.
        local $0 = $args{script} if defined $args{script};
        local @INC = ("lib", @INC);
        eval "use " . ref($cli) . "()";
        die if $@;

        last unless $cli->read_env;
        #$self->log_debug(["skipped file %s (script does not read env)", $filename]);

        my $env_name = $cli->env_name;
        if (!$env_name) {
            $env_name = uc($prog);
            $env_name =~ s/\W+/_/g;
        }

        my @sectpod;
        push @sectpod, "=head2 ", $env_name, " => str\n\n";
        push @sectpod, "Specify additional command-line options\n\n";

        push @{ $resmeta->{'func.sections'} }, {name=>'ENVIRONMENT', content=>join("", @sectpod)};
        push @pod, "=head1 ENVIRONMENT\n\n", @sectpod;
    }

    # sections: CONFIGURATION FILE & FILES
    {
        # workaround because currently the dumped object does not contain all
        # attributes in the hash (Moo/Mo issue?), we need to access the
        # attribute accessor method first to get them recorded in the hash. this
        # will be fixed in the dump module in the future.
        local $0 = $args{script} if defined $args{script};
        local @INC = ("lib", @INC);
        eval "use " . ref($cli) . "()";
        die if $@;

        last unless $cli->read_config;

        my $config_filenames = [];
        my $config_dirs;
        my @files;
        my @sections;

        # section: FILES
        my @files_sectpod;
        {
            if (my $cfns = $cli->config_filename) {
                for my $cfn (ref($cfns) eq 'ARRAY' ? @$cfns : $cfns) {
                    if (ref($cfn) eq 'HASH') {
                        push @$config_filenames, $cfn;
                    } else {
                        push @$config_filenames, {filename=>$cfn};
                    }
                }
            } elsif ($cli->program_name) {
                push @$config_filenames,
                    {filename => $cli->program_name . ".conf"};
            } else {
                push @$config_filenames,
                    {filename => $prog . ".conf"};
            }
            $config_dirs = $cli->{config_dirs} // ['~/.config', '~', '/etc'];

            for my $config_dir (@$config_dirs) {
                for my $cfn (@$config_filenames) {
                    my $p = "$config_dir/$cfn->{filename}";
                    push @files, $p;
                    push @files_sectpod, $cfn->{section} // '';
                    push @files_sectpod, "$p\n\n";
                }
            }
        }

        # section: CONFIGURATION FILE
        {
            use experimental 'smartmatch';

            my @sectpod;

            push @sectpod, (
                "This script can read configuration files. Configuration files are in the format of L<IOD>, which is basically INI with some extra features.\n\n",

                "By default, these names are searched for configuration filenames (can be changed using C<--config-path>): ",
                (map {(
                    # add those pesky comma's/'or's (for two items: A or B, for
                    # >2 items: A, B, or C)
                    (@files == 2 && $_ == 1 ? " or" : ""),
                    (@files >  2 && $_ == $#files ? ", or" : ""),
                    (@files >  2 && $_ >  0 && $_ < $#files ? "," : ""),
                    ($_ > 0 ? " " : ""),
                    "F<$files[$_]>",
                    (defined($sections[$_]) ? " (under the section C<$sections[$_]>)" : ""),
                )} 0..$#files), ".\n\n",

                "All found files will be read and merged.", "\n\n",

                "To disable searching for configuration files, pass C<--no-config>.\n\n",

                ($cli->{subcommands} ? ("To put configuration for a certain subcommand only, use a section name like C<[subcommand=NAME]> or C<[SOMESECTION subcommand=NAME]>.\n\n") : ()),

                "You can put multiple profiles in a single file by using section names like C<[profile=SOMENAME]> or C<[SOMESECTION profile=SOMENAME]>",
                ($cli->{subcommands} ? " or C<[subcommand=SUBCOMMAND_NAME profile=SOMENAME]> or C<[SOMESECTION subcommand=SUBCOMMAND_NAME profile=SOMENAME]>":""), ". ",
                "Those sections will only be read if you specify the matching C<--config-profile SOMENAME>.", "\n\n",

                "You can also put configuration for multiple programs inside a single file, and use filter C<program=NAME> in section names, e.g. C<[program=NAME ...]> or C<[SOMESECTION program=NAME]>. ",
                "The section will then only be used when the reading program matches.\n\n",

                "Finally, you can filter a section by environment variable using the filter C<env=CONDITION> in section names. ",
                "For example if you only want a section to be read if a certain environment variable is true: C<[env=SOMEVAR ...]> or C<[SOMESECTION env=SOMEVAR ...]>. ",
                "If you only want a section to be read when the value of an environment variable has value equals something: C<[env=HOSTNAME=blink ...]> or C<[SOMESECTION env=HOSTNAME=blink ...]>. ",
                "If you only want a section to be read when the value of an environment variable does not equal something: C<[env=HOSTNAME!=blink ...]> or C<[SOMESECTION env=HOSTNAME!=blink ...]>. ",
                "If you only want a section to be read when an environment variable contains something: C<[env=HOSTNAME*=server ...]> or C<[SOMESECTION env=HOSTNAME*=server ...]>. ",
                "Note that currently due to simplistic parsing, there must not be any whitespace in the value being compared because it marks the beginning of a new section filter or section name.\n\n",

                "List of available configuration parameters:\n\n",
            );

            if ($cli->{subcommands}) {
                # first list the options tagged with 'common' and common options
                # (non-function argument options, like --format or --log-level)
                # which are supposed to be the same across subcommands.
                push @sectpod, "=head2 Common for all subcommands\n\n";
                my $param2opts = _list_config_params(
                    $clidocdata{$sc_names[0]},
                    sub { 'common' ~~ @{ $_[0]->{tags} // []} || !$_[0]->{arg} });
                for (sort keys %$param2opts) {
                    push @sectpod, " $_ (see $param2opts->{$_})\n";
                }
                push @sectpod, "\n";

                # now list the options for each subcommand
                for my $sc_name (@sc_names) {
                    my $sc_spec = $cli->{subcommands}{$sc_name};
                    next if $sc_spec->{is_alias};
                    push @sectpod, "=head2 Configuration for subcommand '$sc_name'\n\n";
                    $param2opts = _list_config_params(
                        $clidocdata{$sc_name},
                        sub { !('common' ~~ @{ $_[0]->{tags} // []}) && $_[0]->{arg} });
                    for (sort keys %$param2opts) {
                        push @sectpod, " $_ (see $param2opts->{$_})\n";
                    }
                    push @sectpod, "\n";
                }
            } else {
                my $param2opts = _list_config_params($clidocdata{''});
                for (sort keys %$param2opts) {
                    push @sectpod, " $_ (see $param2opts->{$_})\n";
                }
                push @sectpod, "\n";
            }

            push @{ $resmeta->{'func.sections'} }, {name=>'CONFIGURATION FILE', content=>join("", @sectpod), ignore=>1};
            push @pod, "=head1 CONFIGURATION FILE\n\n", @sectpod;
        }

        push @{ $resmeta->{'func.sections'} }, {name=>'FILES', content=>join("", @files_sectpod)};
        push @pod, "=head1 FILES\n\n", @files_sectpod;
    }

    # section: SEE ALSO
    {
        my @sectpod;

        my %seen_urls;
        for my $sc_name (sort keys %clidocdata) {
            my $meta = $metas{$sc_name};
            next unless $meta->{links};
            for my $link0 (@{ $meta->{links} }) {
                my $link = ref($link0) ? $link0 : {url=>$link0};
                my $url = $link->{url};
                next if $seen_urls{$url}++;
                if ($url =~ s!^(pm|pod|prog):(//?)?!!) {
                    push @sectpod, "L<$url>.";
                } else {
                    push @sectpod, "L<$url>.";
                }
                if ($link->{summary}) {
                    push @sectpod, " $link->{summary}";
                    push @sectpod, "." unless $link->{summary} =~ /\.$/;
                }
                push @sectpod, " " .
                    Markdown::To::POD::markdown_to_pod($link->{description})
                      if $link->{description};
                push @sectpod, "\n\n";
            }
        }

        last unless @sectpod;

        push @{ $resmeta->{'func.sections'} }, {name=>'SEE ALSO', content=>join("", @sectpod)};
        push @pod, "=head1 SEE ALSO\n\n", @sectpod;
    }

    [200, "OK", join("", @pod), $resmeta];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

Please see the included CLI script L<gen-pod-for-pericmd-script>.


=for Pod::Coverage ^(new)$


=head1 SEE ALSO

L<Perinci::CmdLine>

use v6;
use Test;
use X::Data::StaticTable;
unit module Data;

subset StaticTable::Position of Int where * >= 1;



class StaticTable {
    has Position $.columns;
    has Position $.rows;
    has @!data;
    has Str @.header;
    has %.ci; #-- Gets the heading (Str) for a column number (Position)

    method perl {
        my Str $out = "Columns:$!columns Rows:$!rows Elems:" ~ @!data.elems;
        my @headers = gather for %!ci.sort(*.value)>>.kv -> ($k, $v) { take "$v=$k"; }
        $out ~= " Headings:" ~ @headers ;
        return $out;
    }

    method display {
        my Str $out;
        for (1 .. $!rows) -> $row-num {
            $out ~= "\n";
            for (1 .. $!columns) -> $col-num {
                my $cell = self!cell-by-position($col-num, $row-num).perl;
                $out ~= "[" ~ $cell ~ "]\t";
            }
        }
        my Str $header;
        $header = join("\t", @.header);
        my Str @u;
        for (@.header) -> $h {
            @u.append("⋯" x $h.chars);
        }
        return $header ~ "\n" ~ join("\t", @u) ~ $out;
    }

    submethod BUILD (
    :@!data, :@!header, :%!ci, Position :$!columns, Position :$!rows
    ) { }
    method !calculate-dimensions(Position $columns, Int $elems) {
        my $extra-cells = $elems % $columns;
        $extra-cells = $columns - $extra-cells if ($extra-cells > 0);
        my @additional-cells = Nil xx $extra-cells; #'Nil' objects to fill an incomplete row, will appear as 'Any'
        my Position $rows = ($elems + $extra-cells) div $columns;
        return $rows, |@additional-cells;
    }

    multi method new(@header!, +@new-data) { #-- It should be Str @header!
        if (@header.elems < 1) {
            X::Data::StaticTable.new("Header is empty").throw;
        }
        if (@new-data.elems < 1) {
            X::Data::StaticTable.new("No data available").throw;
        }
        my ($rows, @additional-cells) = self!calculate-dimensions(@header.elems, @new-data.elems);
        my Int $col-num = 1;
        my %column-index = ();
        for (@header) -> $heading { %column-index{$heading} = $col-num++; }
        if (@header.elems != %column-index.keys.elems) {
            X::Data::StaticTable.new("Header has repeated elements").throw;
        };

        @new-data.append(@additional-cells);
        return self.bless(
            columns => @header.elems,
            rows    => $rows,
            data    => @new-data,
            header  => @header.map(*.Str),
            ci      => %column-index
        );
    }
    multi method new(Position $columns!, +@new-data) {
        my @header = ('A', 'B' ... *)[0 ... $columns - 1].list;
        self.new(@header, @new-data);
    }

    #== Rowset constructor: just receive an array and do our best to handle it ==
    multi method new(@new-data,         #-- By default, @new-data is an array of arrays
        Bool :$set-of-hashes = False,   #-- Receiving an array with hashes in each element
        Bool :$data-has-header = False, #-- Asume an array of arrays. First row is the header
        :$rejected-data is raw = Nil    #-- Rejected rows or cells will be returned here
    ) {
        if ($set-of-hashes && $data-has-header) {
            X::Data::StaticTable.new("Contradictory flags using the 'rowset' constructor").throw;
        }
        my (@data, @xeno-hash, %xeno-array); #-- @xeno will be used ONLY if rejected-rows is provided
        my @header;

        #-----------------------------------------------------------------------
        if ($set-of-hashes) { #--- HASH MODE -----------------------------------
            # Pass 1: Weed out not-hashes and determine an optimal header
            my %column-frequency;
            my @hashable-data;
            for (@new-data) -> $row-ref {
                if ($row-ref ~~ Hash) { # Sort Columns so most common ones appear at first
                    my %row = %$row-ref;
                    for (%row.keys) { %column-frequency{$_}++ }
                    push @hashable-data, $row-ref;
                } else {
                    push @xeno-hash, $row-ref if ($rejected-data.defined);
                }
            }
            @header = %column-frequency.sort({ -.value, .key }).map: (*.keys[0]);
            if (@hashable-data.elems == 0) {
                X::Data::StaticTable.new("No data available").throw;
            }
            # Pass 2: Populate with data
            for (@hashable-data) -> $hash-ref {
                my %row = %$hash-ref;
                for (@header) -> $heading {
                    push @data, (%row{$heading}.defined) ?? %row{$heading} !! Nil;
                }
            }
            @$rejected-data = @xeno-hash if ($rejected-data.defined);
        } else { #--- ARRAY MODE -----------------------------------------------
            my Data::StaticTable::Position $columns;
            my $first-data-row = 0;
            if ($data-has-header) {
                @header = @new-data[0];
                @header = @header>>[].flat; #-- Completely flatten the header
                $columns = @header.elems;
                $first-data-row = 1;
            } else {
                $columns = @new-data.max(*.elems).elems;
                @header = ('A', 'B' ... *)[0 ... $columns - 1].list;
            }
            my $i = 1;
            for (@new-data[$first-data-row ... *]) -> $row-ref {
                my @row = @$row-ref;
                %xeno-array{$i} = @row.splice($columns) if (@row.elems > $columns);
                push @row, |(Nil xx $columns - @row.elems) if @row.elems < $columns;
                push @data, |@row;
                $i++;
            }
            %$rejected-data = %xeno-array if ($rejected-data.defined);
        } #---------------------------------------------------------------------
        return self.new(@header, @data);
    }

    #-- Accessing cells directly
    method !cell-by-position(Position $col!, Position $row!) {
        my $pos = ($!columns * ($row-1)) + $col - 1;
        if ($pos < @!data.elems) { return @!data[$pos]; }
        X::Data::StaticTable.new("Out of bounds").throw;
    }
    method cell(Str $column-header, Position $row) {
        my Position $column-number = self!column-number($column-header);
        return self!cell-by-position($column-number, $row);
    }

    #-- Retrieving a column by its name
    method !column-number(Str $heading) {
        if (%!ci{$heading}:exists) { return %!ci{$heading}; }
        X::Data::StaticTable.new("Heading $heading not found").throw;
    }

    method column(Str $heading) {
        my Position $column-number = self!column-number($heading);
        my Int $pos = $column-number - 1;
        return @!data[$pos+($!columns*0), $pos+($!columns*1) ... *];
    }

    #-- Retrieving specific rows
    method row(Position $row) {
        if (($row < 1) || ($row > $.rows)) {
            X::Data::StaticTable.new("Out of bounds").throw;
        }
        return @!data[($row-1) * $!columns ... $row * $!columns - 1];
    }
    method !rows(@rownums) {
        my @result = gather for (@rownums) -> $num { take self.row($num) };
        return @result;
    }

    #-- Shaped arrays
    #-- Perl6 shaped arrays:  @a[3;2] <= 3 rows and 2 columns, starts from 0
    #-- This method returns the data only (not headers)
    method shaped-array() {
        my @shaped;
        my @rows = self!rows(1 .. $.rows);
        for (1 .. $.rows) -> $r {
            my @row = @rows[$r];
            for (1 .. $.columns) -> $c {
                @shaped[$r - 1;$c - 1] = self!cell-by-position($c, $r);
            }
        }
        return @shaped;
    }

    #==== Positional =====
    multi method elems(::?CLASS:D:) {
        return @!data.elems;
    }

    method AT-POS(::?CLASS:D: Position $row) {
        return @.header.list if ($row == 0);
        my @row = self.row($row);
        my %full-row;
        for (0 .. $.columns - 1) -> $i {
            %full-row{@.header[$i]} = @row[$i];
        }
        return %full-row;
    }

    #==== Index ====
    method generate-index(Str $heading) {
        my %index;
        my Position $row-num = 1;
        my @full-column = self.column($heading);
        for (@full-column) -> $item {
            if ($item.defined) {
                if (%index{$item}:exists == False) {
                    my Position @a = ();
                    %index{$item} = @a;
                }
                push %index{$item}, $row-num++;
            }
        }
        return %index;
    }

    #--- Returns raw data cells from a set of rows
    #--- Any repeated row is ignored (recovers only one)
    method !gather-rowlist(Array[Position] $_rownums) {
        my @rownums = gather for ($_rownums) -> $n { take $n };
        @rownums = @rownums.unique.sort;
        if (@rownums.elems == 0) {
            X::Data::StaticTable.new("No data available").throw;
        }
        #-- If we are receiving the output from generate-index, it might be
        #-- possible that elements of @rownums are also arrays
        @rownums = @rownums>>[].flat;
        if any(@rownums) > $.rows {
            X::Data::StaticTable.new("No data available").throw;
        }
        my @result = ();
        if (@rownums.elems == 1) {
            @result = self.row(@rownums[0])
        } else {
            #--- Instead of getting row by row, we
            #--- get whole blocks of continous rows.
            my @block;
            my @rowsets;
            @rownums.rotor(2 => -1).map: -> ($a,$b) {
                push @block, $a;
                if ($a+1 != $b) {
                    @rowsets.push( $(@block.clone) );
                    @block = ();
                };
                LAST {
                	push @block, $b;
                	@rowsets.push( $(@block.clone) );
                }
            };
            #-- TODO: get a little bit more speed? We only need the min and
            #-- max of each block when populating above, hence avoiding to use
            #-- .min and .max functions below
            for (@rowsets) -> $block-num {
                my $min-row = $block-num.min;
                my $max-row = $block-num.max;
                my $start = ($!columns * ($min-row - 1)); #1st element of the first row
                my $end = ($!columns * ($max-row - 1)) + $!columns - 1; #last element of the last row
                @result.append(@!data[$start ... $end]);
            }
        }
        return @result;
    }

    method take(Array[Position] $_rownums) {
        return self.new(@!header, self!gather-rowlist($_rownums));
    }
}

#------------------------------------------------------------------------------#
#------------------------------------------------------------------------------#

class StaticTable::Query {
    has %!indexes handles <keys elems values kv AT-KEY EXISTS-KEY>;
    #-- Cache
    has %!stored-rownumbers;
    has Data::StaticTable $!T;
    submethod BUILD (:$!T) { }

    method perl {
        my Str $out;
        return "No columns indexed." if (%!indexes.keys.elems == 0);
        $out ~= %!indexes.keys.elems ~ " of " ~ $!T.columns ~ " columns indexed. Unique values per each:";
        for ($!T.header) -> $heading {
            if (%!indexes{$heading}:exists) {
                my %one-index = %!indexes{$heading};
                my Int $distinct-elements = %one-index.keys.elems;
                $out ~= " '$heading'=$distinct-elements";
            }
        }
        return $out;
    }

    method grep(Str $heading, Mu $matcher where { -> Regex {}($_); True }) {
        my Data::StaticTable::Position @rownums;
        if (%!indexes{$heading}:exists) { #-- Search in the index if it is available. Should be faster.
            my @keysearch = grep {.defined and $matcher}, %!indexes{$heading}.keys;
            for (@keysearch) -> $k {
                @rownums.push(|%!indexes{$heading}{$k});
            }
        } else {;
            @rownums = 1 <<+>> ( grep {.defined and $matcher}, :k, $!T.column($heading) );
        }
        return @rownums.sort.list;
    }

    method new(Data::StaticTable $T) {
        self.bless(T => $T);
    }

    #==== Index ====
    method add-index(Str $heading) {
        my %index;
        my Data::StaticTable::Position $row-num = 1;
        my @full-column = $!T.column($heading);
        for (@full-column) -> $item {
            if ($item.defined) {
                if (%index{$item}:exists == False) {
                    my Data::StaticTable::Position @a = ();
                    %index{$item} = @a;
                }
                push %index{$item}, $row-num++;
            }
        }
        %!indexes{$heading} = %index;
        my $score = (%index.keys.elems / @full-column.elems).Rat;
        return $score;
    }
}

=begin pod

=head1 Introduction

StaticTable allws you to handle bidimensional data in a more natural way
Some features:

=item Rows starts at 1 (C<Position> is the datatype used to reference row numbers)

=item Columns have header names

=item Any column can work as an index

If the number of elements provided does not suffice to form a
square or a rectangle, empty cells will be added.

The module provides two classes: C<StaticTable> and C<StaticTable::Query>.

A StaticTable can be populated, but it can not be modified later. To perform
searchs and create/store indexes, a Query object is provided. You can add
indexes per column, and perform searches (grep) later. If an index exists, it
will be used.

You can get data by rows, columns, and create subsets by taking some
rows from an existing StaticTable.

=back

=head1 Types

=head2 C<Data::StaticTable::Position>

Basically, an integer greater than 0. Used to indicate a row position
in the table. A StaticTable do not have rows on index 0.

=head1 C<Data::StaticTable> class

=head2 Positional features

You can use [n] to get the full Nth row, in the way of a hash of
B<'Column name' => data>

 $Q1[10]<Column3>

would refer to the data in Row 10, with the heading Column3

=head2 C<method new>

 my $t = StaticTable.new( 3 , (1 .. 15) );
 my $t = StaticTable.new(
    <Column1 Column2 Column3> ,
    (
    1, 2, 3,
    4, 5, 6,
    7, 8, 9,
    10,11,12
    13,14,15
    )
 );

Create a StaticTable, by specifying a header (one by one or just by numbers). If
you use numbers, columns will be automatically named as A, B, C ... Z, AA, AB, ...

This will create a spreadsheet-like table, with numbered rows and labelled
columns.

If you do not provide enough data to fill the last row, empty cels will be
appended.

=head2 C<method perl>

Shows a summary of the things contained in the Query object. Used for debugging,
B<not for serialization>.

=head2 C<method display>

Shows the contents of the StaticTable Used for debugging, B<not for
serialization>.

=head2 C<method cell(Str $column-header, Position $row)>

Retrieves the content of a cell.

=head2 C<method column(Str $column-header)>

Retrieves the content of a column like a regular C<List>.

=head2 C<method row(Position $row)>

Retrieves the content of a row as a regular C<List>.

=head2 C<method shaped-array()>

Retrieves the content of a row as a multiple dimension array.

=head2 C<method elems()>

Retrieves the number of cells in the table

=head2 C<method generate-index(Str $heading)>

Generate a C<Hash>, where the  key is the value of the cell, and the values
is a list of row numbers (of type C<Data::StaticTable::Position>).

=head2 C<method take(Array[Position] $_rownums)>

Generate a new C<StaticTable>, using a list of row numbers
(using the type C<Data::StaticTable::Position>)

=head1 C<Data::StaticTable::Query> class

Since StaticTable is immutable, a helper class to perform searches is provided.
It can contain generated indexes. If an index is provided, it will be used if a
search is performed.

=head2 Associative features

You can use hash-like keys, to get a specific index for a column

 $Q1<Column1>
 $Q1{'Column1'}

Both can get you the index (sames as generated by C<generate-index> in a
C<StaticTable>).

=head2 C<method new(Data::StaticTable $T)>

You need to specify an existing C<StaticTable> to create this object.

=head2 C<method perl>

Shows a summary of the data contained in the Query object. Used for debugging,
B<not for serialization>.

=head2 C<method keys>

Returns the name of the columns indexed.

=head2 C<method values>

Returns the values indexed.

=head2 C<method kv>

Returns the hash of the same indexes in the C<Query> object.

=head2 C<method  grep(Str $heading, Mu $matcher where { -> Regex {}($_); True })>

Allows to use grep over a column. It returns a list of row numbers where a
regular expression matches.

You can not only use a regxep, but a C<Junction> or C<Regex> elements.

=end pod

# vim: ft=perl6

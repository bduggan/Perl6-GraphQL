use GraphQL::Types;

unit class GraphQL::Actions;
#
# There are two "top level" rules, <Document> for a GraphQL query document,
# and <TypeSchema> for a GraphQL type schema.
#

#
# Only for <TypeSchema>, as fields and lists are defined, keep track
# of any that refer to types, then after all the types are defined,
# loop through them, linking to the created types.  This allows, for
# example, a field of an Object to refer to another Object of the same
# type.
#
has @!fields-to-type;  # These types have a single type
# 'typename' => GraphQL::Field or GraphQL::InputValue (set $.type)
#            or GraphQL::Non-Null or GraphQL::List    (set $.ofType)

has @!lists-to-type;   # These take lists of types
# ('list', 'of', 'typenames') => GraphQL::Object (set $.interfaces)
#                             or GraphQL::Union  (set $.possibleTypes)

#
# Returns this (in .made) when making a <Document>
#
has GraphQL::Document $!q = GraphQL::Document.new;

#
# Returns this (in .made) when making a <TypeSchema>
#
has GraphQL::Schema $!s = GraphQL::Schema.new;

method Document($/)
{
    if $!q.operations{''} and $!q.operations.elems() != 1
    {
        die "This anonymous operation must be the only defined operation";
    }

    make $!q;
}

method OperationDefinition($/)
{
    my $name = $<Name> ?? $<Name>.made !! '';

    die "Duplicate definition of $name" if $!q.operations{$name}.defined;

    $!q.operations{$name} = GraphQL::Operation.new(
        name         => $name,
        operation    => $<OperationType> ?? $<OperationType>.Str !! 'query',
        selectionset => $<SelectionSet>.made
    );
}

method SelectionSet($/)
{
    make $<Selection>».made
}

method Selection($/)
{
    make $<Field>.made // $<FragmentSpread>.made // $<InlineFragment>.made;
}

method Field($/)
{
    make GraphQL::QueryField.new(
        alias        => $<Alias>.made,
        name         => $<Name>.made,
        args         => $<Arguments>.made    // (),
        directives   => $<Directives>.made   // (),
        selectionset => $<SelectionSet>.made // ()
    );
}

method Alias($/)
{
    make $<Name>.made;
}

method Arguments($/)
{
    make $<Argument>».made;
}

method Argument($/)
{
    make GraphQL::Argument.new(
        name => $<Name>.made,
        value => $<Value>.made
    );
}

method FragmentSpread($/)
{
    make GraphQL::FragmentSpread.new(
        name => $<FragmentName>.made,
        directives => $<Directives>.made
    );
}

method InlineFragment($/)
{
}

method FragmentDefinition($/)
{
    $!q.fragments{$<FragmentName>.made} = GraphQL::Fragment.new(
        name         => $<FragmentName>.made,
        onType       => $<TypeCondition>.made,
        directives   => $<Directives>.made,
        selectionset => $<SelectionSet>.made
    );
}

method FragmentName($/)
{
    make $<Name>.Str;
}

method TypeCondition($/)
{
    make $<NamedType>.made;
}

method Name($/)
{
    make $/.Str;
}

method Value:sym<FloatValue>($/)
{
    make $/.Num;
}

method Value:sym<IntValue>($/)
{
    make $/.Int;
}

method Value:sym<StringValue>($/)
{
    make $/.Str;
}

method Value:sym<BooleanValue>($/)
{
    make $/.Str;
}

method Value:sym<NullValue>($/)
{
    make 'null'
}

method Type($/)
{
    make $<NonNullType>.made // $<NamedType>.made // $<ListType>.made;
}

method NamedType($/)
{
    make $<Name>.Str;
}

method ListType($/)
{
    if $<Type>.made ~~ Str
    {
        my $l = GraphQL::List.new();
        push @!fields-to-type, $<Type>.made => $l;
        make $l;
    }
    else
    {
        make GraphQL::List.new(ofType => $<Type>.made);
    }
}

method NonNullType($/)
{
    my $type = $<NamedType>.made || $<ListType>.made;

    if $type ~~ Str
    {
        my $n = GraphQL::Non-Null.new();
        push @!fields-to-type, $type => $n;
        make $n;
    }
    else
    {
        make GraphQL::Non-Null.new(ofType => $type);
    }
}

method InterfaceDefinition($/)
{
    make $!s.types{$<Name>.made} =
        GraphQL::Interface.new(name => $<Name>.made,
                               fields => $<FieldDefinitionList>.made);
}

method FieldDefinitionList($/)
{
    my $fieldlist = GraphQL::FieldList.new;
    for $<FieldDefinition> -> $field
    {
        $fieldlist{$field.made.name} = $field.made
    }
    make $fieldlist;
}

method FieldDefinition($/)
{
    if $<Type>.made ~~ Str
    {
        my $f = GraphQL::Field.new(
            name => $<Name>.made,
            args => $<ArgumentDefinitions>.made // (),
        );
        push @!fields-to-type, $<Type>.made => $f;
        make $f;
    }
    else
    {
        make GraphQL::Field.new(
            name => $<Name>.made,
            type => $<Type>.made,
            args => $<ArgumentDefinitions>.made // ()
        );
    }
}

method ObjectTypeDefinition($/)
{
    my $o = GraphQL::Object.new(name => $<Name>.made,
                                fields => $<FieldDefinitionList>.made);

    $!s.types{$<Name>.made} = $o;

    if $<ImplementsDefinition>.made
    {
        push @!lists-to-type, 
             ($<ImplementsDefinition>.made => $o);
    }
}

method ImplementsDefinition($/)
{
    make $<Name>».made;
}

method UnionDefinition($/)
{
    my $u = GraphQL::Union.new(name => $<Name>.made);

    $!s.types{$<Name>.made} = $u;

    push @!lists-to-type, ($<UnionList>.made => $u);
}

method UnionList($/)
{
    make $<Name>».made; 
}

method EnumDefinition($/)
{
    $!s.types{$<Name>.made} =
        GraphQL::Enum.new(name => $<Name>.made,
                          enumValues => $<EnumValues>.made);
}

method EnumValues($/)
{
    make set $<Name>.map({.made});
}

method DefaultValue($/)
{
    make $<Value>.made;
}

method ArgumentDefinition($/)
{
    if $<Type>.made ~~ Str
    {
        my $t = GraphQL::InputValue.new(name => $<Name>.made,
                                        defaultValue => $<DefaultValue>.made);

        push @.fields-to-type, $<Type>.made => $t;

        make $t;
    }
    else
    {
        make GraphQL::InputValue.new(name => $<Name>.made,
                                     type => $<Type>.made,
                                     defaultValue => $<DefaultValue>.made);
    }
}

method ArgumentDefinitions($/)
{
    make $<ArgumentDefinition>».made;
}

method ScalarDefinition($/)
{
    $!s.types{$<Name>.made} = GraphQL::Scalar.new(name => $<Name>.made);
}

method TypeSchema($/)
{
    #
    # Go through all the saved @fields-to-type and @lists-to-type, look
    # them up in the schema type list, and patch them to the right type
    # now that they are all defined
    #
    for @!fields-to-type -> $field
    {
        die "Haven't defined $field.key()" unless $!s.types{$field.key};

        given $field.value
        {
            when GraphQL::Field | GraphQL::InputValue
            {
                $field.value.type = $!s.types{$field.key}
            }
            when GraphQL::Non-Null | GraphQL::List
            {
                $field.value.ofType = $!s.types{$field.key};
            }
        }
    }

    for @!lists-to-type -> $typelist
    {
        my @list-of-types;
        for $typelist.key -> $name
        {
            die "Haven't defined interface $name" unless $!s.types{$name};
            push @list-of-types, $!s.types{$name};
        }
        
        given $typelist.value
        {
            when GraphQL::Object
            { 
                $typelist.value.interfaces = @list-of-types
            }
            when GraphQL::Union
            {
                $typelist.value.possibleTypes = set @list-of-types
            }
        }
    }

    die "Missing root query type $!s.query()" 
        unless $!s.type() and $!s.type().kind ~~ 'OBJECT';

    make $!s;
}

method SchemaDefinition($/)
{
    $!s.query = $<SchemaQuery>.made;
}

method SchemaQuery($/)
{
    make $<Name>.made;
}

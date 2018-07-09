# Required interface for existing parser implementations
module Sparkql::ParserCompatibility

  MAXIMUM_MULTIPLE_VALUES = 200
  MAXIMUM_EXPRESSIONS = 75
  MAXIMUM_LEVEL_DEPTH = 2

  OPERATORS_SUPPORTING_MULTIPLES = ["Eq","Ne"]

  # To be implemented by child class.
  # Shall return a valid query string for the respective database,
  # or nil if the source could not be processed.  It may be possible to return a valid
  # SQL string AND have errors ( as checked by errors? ), but this will be left
  # to the discretion of the child class.
  def compile( source, mapper )
   raise NotImplementedError
  end

  # Returns a list of expressions tokenized in the following format:
  # [{ :field => IdentifierName, :operator => "Eq", :value => "'Fargo'", :type => :character, :conjunction => "And" }]
  # This step will set errors if source is not syntactically correct.
  def tokenize( source )
    raise ArgumentError, "You must supply a source string to tokenize!" unless source.is_a?(String)

    # Reset the parser error stack
    @errors = []

    expressions = self.parse(source)
    expressions
  end

  # Returns an array of errors.  This is an array of ParserError objects
  def errors
    @errors = [] unless defined?(@errors)
    @errors
  end

  # Delegator for methods to process the error list.
  def process_errors
    Sparkql::ErrorsProcessor.new(@errors)
  end

  # delegate :errors?, :fatal_errors?, :dropped_errors?, :recovered_errors?, :to => :process_errors
  # Since I don't have rails delegate...
  def errors?
    process_errors.errors?
  end
  def fatal_errors?
    process_errors.fatal_errors?
  end
  def dropped_errors?
    process_errors.dropped_errors?
  end
  def recovered_errors?
    process_errors.recovered_errors?
  end

  # Maximum supported nesting level for the parser filters
  def max_level_depth
    MAXIMUM_LEVEL_DEPTH
  end

  def max_expressions
    MAXIMUM_EXPRESSIONS
  end

  def max_values
    MAXIMUM_MULTIPLE_VALUES
  end

  private

  def tokenizer_error( error_hash )

    if @lexer
      error_hash[:token_index] = @lexer.token_index
    end

    self.errors << Sparkql::ParserError.new( error_hash )
  end
  alias :compile_error :tokenizer_error

  # Checks the type of an expression with what is expected.
  def check_type!(expression, expected, supports_nulls = true)
    if expected == expression[:type] || check_function_type?(expression, expected) ||
      (supports_nulls && expression[:type] == :null)
      return true
    # If the field will be passed into a function,
    # check the type of the return value (:field_function_type),
    # and coerce if necessary.
    elsif expression[:field_function_type] &&
          expression[:type] == :integer && 
          expression[:field_function_type] == :decimal
      expression[:type] = :decimal
      expression[:cast] = :integer
      return true
    elsif expected == :datetime && expression[:type] == :date
      expression[:type] = :datetime
      expression[:cast] = :date
      return true
    elsif expected == :date && expression[:type] == :datetime 
      expression[:type] = :date
      expression[:cast] = :datetime
      if multiple_values?(expression[:value])
        expression[:value].map!{ |val| coerce_datetime val }
      else
        expression[:value] = coerce_datetime expression[:value]
      end
      return true
    elsif expected == :decimal && expression[:type] == :integer
      expression[:type] = :decimal
      expression[:cast] = :integer
      return true
    end
    type_error(expression, expected)
    false
  end

  def type_error( expression, expected )
      compile_error(:token => expression[:field], :expression => expression,
            :message => "expected #{expected} but found #{expression[:type]}",
            :status => :fatal )
  end
  
  # If a function is being applied to a field, we check that the return type of
  # the function matches what is expected, and that the function supports the
  # field type as the first argument.
  def check_function_type?(expression, expected)
    return false unless expression[:field_function_type] == expression[:type]
    # Lookup the function arguments
    function = Sparkql::FunctionResolver::SUPPORTED_FUNCTIONS[expression[:field_function].to_sym]
    return false if function.nil?

    Array(function[:args].first).include?(expected)
  end

  def coerce_datetime datetime
    if datestr = datetime.match(/^(\d{4}-\d{2}-\d{2})/)
      datestr[0]
    else
      datetime
    end
  end

end

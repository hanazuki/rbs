# frozen_string_literal: true

require 'rbs'

class RDoc::Parser::RBS < RDoc::Parser
  parse_files_matching(/\.rbs$/)

  def initialize(top_level, file_name, content, options, stats)
    super
  end

  def scan
    ast = ::RBS::Parser.parse_signature(@content)
    ast.each do |decl|
      parse_member(decl: decl, context: @top_level)
    end
  end

  def parse_member(decl:, context:, outer_name: nil)
    case decl
    when ::RBS::AST::Declarations::Class
      parse_class_decl(decl: decl, context: context, outer_name: outer_name)
    when ::RBS::AST::Declarations::Module
      parse_module_decl(decl: decl, context: context, outer_name: outer_name)
    when ::RBS::AST::Declarations::Constant
      context = @top_level.find_class_or_module outer_name.to_s if outer_name
      parse_constant_decl(decl: decl, context: context, outer_name: outer_name)
    when ::RBS::AST::Members::MethodDefinition
      context = @top_level.find_class_or_module outer_name.to_s if outer_name
      parse_method_decl(decl: decl, context: context, outer_name: outer_name)
    when ::RBS::AST::Members::Alias
      context = @top_level.find_class_or_module outer_name.to_s if outer_name
      parse_method_alias_decl(decl: decl, context: context, outer_name: outer_name)
    when ::RBS::AST::Members::AttrReader, ::RBS::AST::Members::AttrWriter, ::RBS::AST::Members::AttrAccessor
      context = @top_level.find_class_or_module outer_name.to_s if outer_name
      parse_attr_decl(decl: decl, context: context, outer_name: outer_name)
    end
  end

  def parse_class_decl(decl:, context:, outer_name: nil)
    full_name = fully_qualified_name(outer_name: outer_name, decl: decl)
    klass = context.add_class(RDoc::NormalClass, full_name.to_s, decl.super_class&.name&.to_s || "::Object")
    klass.add_comment(construct_comment(context: context, comment: decl.comment.string), context) if decl.comment
    decl.members.each { |member| parse_member(decl: member, context: context, outer_name: full_name) }
  end

  def parse_module_decl(decl:, context:, outer_name: nil)
    full_name = fully_qualified_name(outer_name: outer_name, decl: decl)
    kmodule = context.add_module(RDoc::NormalModule, full_name.to_s)
    kmodule.add_comment(construct_comment(context: context, comment: decl.comment.string), context) if decl.comment
    decl.members.each { |member| parse_member(decl: member, context: context, outer_name: outer_name) }
  end

  def parse_constant_decl(decl:, context:, outer_name: nil)
    comment = decl.comment ? construct_comment(context: context, comment: decl.comment.string) : nil
    constant = RDoc::Constant.new(decl.name.to_s, decl.type.to_s, comment)
    context.add_constant(constant)
  end

  def parse_method_decl(decl:, context:, outer_name: nil)
    method = RDoc::AnyMethod.new(nil, decl.name.to_s)
    method.singleton = decl.singleton?
    method.visibility = decl.visibility
    method.call_seq = decl.types.map { |type| "#{decl.name.to_s}#{type.to_s}" }.join("\n")
    if decl.location
      method.start_collecting_tokens
      method.add_token({ line_no: 1, char_no: 1, kind: :on_comment, text: "# File #{@top_level.relative_name}, line(s) #{decl.location.start_line}:#{decl.location.end_line}\n" })
      method.add_token({ line_no: 1, char_no: 1, text: decl.location.source })
      method.line = decl.location.start_line if decl.location
    end
    method.comment = construct_comment(context: context, comment: decl.comment.string) if decl.comment
    context.add_method(method)
  end

  def parse_method_alias_decl(decl:, context:, outer_name: nil)
    alias_def = RDoc::Alias.new(nil, decl.old_name.to_s, decl.new_name.to_s, nil, decl.kind == :singleton)
    alias_def.comment = construct_comment(context: context, comment: decl.comment.string) if decl.comment
    context.add_alias(alias_def)
  end

  def parse_attr_decl(decl:, context:, outer_name: nil)
    rw = case decl
         when ::RBS::AST::Members::AttrReader
           'R'
         when ::RBS::AST::Members::AttrWriter
           'W'
         when ::RBS::AST::Members::AttrAccessor
           'RW'
         end
    attribute = RDoc::Attr.new(nil, decl.name.to_s, rw, nil, decl.kind == :singleton)
    attribute.visibility = decl.visibility
    attribute.comment = construct_comment(context: context, comment: decl.comment.string) if decl.comment
    context.add_attribute(attribute)
  end

  private

  def construct_comment(context:, comment:)
    comment = RDoc::Comment.new(comment, context)
    comment.format = "markdown"
    comment
  end

  def fully_qualified_name(outer_name:, decl:)
    if outer_name
      (outer_name + decl.name)
    else
      decl.name
    end
  end
end

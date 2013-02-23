# -*- coding: utf-8 -*-
# = Informations
#
# == License
#
# Ekylibre - Simple ERP
# Copyright (C) 2009-2013 Brice Texier, Thibaud Merigon
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: products
#
#  active                   :boolean          not null
#  address_id               :integer
#  area_measure             :decimal(19, 4)
#  area_unit_id             :integer
#  asset_id                 :integer
#  born_at                  :datetime
#  content_maximal_quantity :decimal(19, 4)   default(0.0), not null
#  content_nature_id        :integer
#  content_unit_id          :integer
#  created_at               :datetime         not null
#  creator_id               :integer
#  current_place_id         :integer
#  dead_at                  :datetime
#  description              :text
#  external                 :boolean          not null
#  father_id                :integer
#  id                       :integer          not null, primary key
#  identification_number    :string(255)
#  lock_version             :integer          default(0), not null
#  maximal_quantity         :decimal(19, 4)   default(0.0), not null
#  minimal_quantity         :decimal(19, 4)   default(0.0), not null
#  mother_id                :integer
#  name                     :string(255)      not null
#  nature_id                :integer          not null
#  number                   :string(255)      not null
#  owner_id                 :integer          not null
#  parent_place_id          :integer
#  picture_content_type     :string(255)
#  picture_file_name        :string(255)
#  picture_file_size        :integer
#  picture_updated_at       :datetime
#  real_quantity            :decimal(19, 4)   default(0.0), not null
#  reproductor              :boolean          not null
#  reservoir                :boolean          not null
#  sex                      :string(255)
#  shape                    :spatial({:srid=>
#  tracking_id              :integer
#  tractor_id               :integer
#  type                     :string(255)      not null
#  unit_id                  :integer          not null
#  updated_at               :datetime         not null
#  updater_id               :integer
#  variety_id               :integer          not null
#  virtual_quantity         :decimal(19, 4)   default(0.0), not null
#  work_number              :string(255)
#


class Product < Ekylibre::Record::Base
  attr_accessible :nature_id, :number, :identification_number, :work_number, :born_at, :sex, :picture, :owner_id
  belongs_to :nature, :class_name => "ProductNature"
  belongs_to :variety, :class_name => "ProductVariety"
  belongs_to :unit
  belongs_to :tracking
  belongs_to :father, :class_name => "Product"
  belongs_to :mother, :class_name => "Product"
  belongs_to :owner, :class_name => "Entity"
  has_many :memberships, :class_name => "ProductMembership"
  has_many :indicators, :class_name => "ProductIndicator"
  has_many :operations, :foreign_key => :target_id
  has_many :product_localizations
  has_attached_file :picture, {
    :url => '/backend/:class/:id/picture/:style',
    :path => ':rails_root/private/:class/:attachment/:id_partition/:style.:extension',
    :styles => {
      :thumb => ["64x64#", :jpg],
      :identity => ["180x180", :jpg],
      :large => ["600x600", :jpg]
    }
  }

  default_scope -> { order(:name) }
  scope :members_of, lambda { |group, viewed_at| where("id IN (SELECT product_id FROM #{ProductMembership.table_name} WHERE group_id = ? AND ? BETWEEN COALESCE(started_at, ?) AND COALESCE(stopped_at, ?))", group.id, viewed_at, viewed_at, viewed_at)}


  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_numericality_of :picture_file_size, :allow_nil => true, :only_integer => true
  validates_numericality_of :area_measure, :content_maximal_quantity, :maximal_quantity, :minimal_quantity, :real_quantity, :virtual_quantity, :allow_nil => true
  validates_length_of :identification_number, :name, :number, :picture_content_type, :picture_file_name, :sex, :work_number, :allow_nil => true, :maximum => 255
  validates_inclusion_of :active, :external, :reproductor, :reservoir, :in => [true, false]
  validates_presence_of :content_maximal_quantity, :maximal_quantity, :minimal_quantity, :name, :nature, :number, :owner, :real_quantity, :unit, :variety, :virtual_quantity
  #]VALIDATORS]
  validates_presence_of :nature, :name, :owner

  accepts_nested_attributes_for :memberships, :reject_if => :all_blank, :allow_destroy => true
  accepts_nested_attributes_for :indicators, :reject_if => :all_blank, :allow_destroy => true
  delegate :serial_number, :producer, :to => :tracking

  before_validation do
    if self.nature
      self.variety_id = self.nature.variety_id
      self.unit_id = self.nature.unit_id
    end
  end

  def default_price(category_id)
    self.nature.default_price(category_id)
  end


  # Add an operation for the product
  def operate(action, *args)
    options = (args[-1].is_a?(Hash) ? options.delete_at(-1) : {})
    if operand = (args[0].is_a?(Product) ? args[0] : nil)
      options[:operand] = operand
    end
    return self.operations.create(options)
  end

  # Returns groups of the product at a given time (or now by default)
  def groups_at(viewed_at = nil)
    ProductGroup.groups_of(self, viewed_at || Time.now)
  end


end

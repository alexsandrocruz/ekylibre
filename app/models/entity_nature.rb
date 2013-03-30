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
# == Table: entity_natures
#
#  active           :boolean          default(TRUE), not null
#  created_at       :datetime         not null
#  creator_id       :integer
#  description      :text
#  full_name_format :string(255)
#  gender           :string(255)      not null
#  id               :integer          not null, primary key
#  in_name          :boolean          default(TRUE), not null
#  lock_version     :integer          default(0), not null
#  name             :string(255)      not null
#  title            :string(255)
#  updated_at       :datetime         not null
#  updater_id       :integer
#


class EntityNature < Ekylibre::Record::Base
  attr_accessible :active, :description, :full_name_format, :in_name, :name, :gender, :title
  enumerize :gender, :in => [:organization, :woman, :man, :undefined], :default => :undefined, :predicates => true
  has_many :entities, :foreign_key => :nature_id, :inverse_of => :nature
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_length_of :full_name_format, :gender, :name, :title, :allow_nil => true, :maximum => 255
  validates_inclusion_of :active, :in_name, :in => [true, false]
  validates_presence_of :gender, :name
  #]VALIDATORS]
  validates_uniqueness_of :name

  default_scope -> { order(:name) }

  before_validation do
    self.in_name = false if self.man? or self.woman?
    if self.man? or self.woman?
      self.full_name_format ||= '[title] [last_name] [first_name]'
    else
      self.full_name_format ||= '[last_name]'
    end
  end

  protect(:on => :destroy) do
    self.entities.count <= 0
  end

  # Loads default basic entity natures
  def self.load_defaults
    for gender in self.gender.values
      unless self.find_by_gender(gender)
        attrs = "models.entity_nature.default.#{gender}".t.symbolize_keys
        self.create!(attrs.merge(:gender => gender, :in_name => false))
      end
    end
  end

end

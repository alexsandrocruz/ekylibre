# -*- coding: utf-8 -*-
# = Informations
#
# == License
#
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2009 Brice Texier, Thibaud Merigon
# Copyright (C) 2010-2012 Brice Texier
# Copyright (C) 2012-2015 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: products
#
#  address_id            :integer
#  born_at               :datetime
#  category_id           :integer          not null
#  created_at            :datetime         not null
#  creator_id            :integer
#  dead_at               :datetime
#  default_storage_id    :integer
#  derivative_of         :string
#  description           :text
#  extjuncted            :boolean          default(FALSE), not null
#  fixed_asset_id        :integer
#  id                    :integer          not null, primary key
#  identification_number :string
#  initial_born_at       :datetime
#  initial_container_id  :integer
#  initial_dead_at       :datetime
#  initial_enjoyer_id    :integer
#  initial_father_id     :integer
#  initial_geolocation   :geometry({:srid=>4326, :type=>"point"})
#  initial_mother_id     :integer
#  initial_owner_id      :integer
#  initial_population    :decimal(19, 4)   default(0.0)
#  initial_shape         :geometry({:srid=>4326, :type=>"geometry"})
#  lock_version          :integer          default(0), not null
#  name                  :string           not null
#  nature_id             :integer          not null
#  number                :string           not null
#  parent_id             :integer
#  person_id             :integer
#  picture_content_type  :string
#  picture_file_name     :string
#  picture_file_size     :integer
#  picture_updated_at    :datetime
#  tracking_id           :integer
#  type                  :string
#  updated_at            :datetime         not null
#  updater_id            :integer
#  variant_id            :integer          not null
#  variety               :string           not null
#  work_number           :string
#


class LandParcel < Easement
  # has_many :members, class_name: "CultivableZoneMembership"
  has_many :zone_memberships, class_name: "CultivableZoneMembership"
  has_many :memberships, class_name: "CultivableZoneMembership", foreign_key: :member_id
  has_many :cultivable_zones, class_name: "CultivableZone", through: :memberships, source: :group
  has_many :product_memberships, class_name: "ProductMembership", foreign_key: :member_id
  has_many :groups, class_name: "Product", through: :product_memberships, source: :group

  scope :members_of_zone, lambda { |group|
    where("id IN (SELECT member_id FROM #{CultivableZoneMembership.table_name} WHERE group_id = ?)", group.id)
  }
  scope :zone_members_of, lambda { |group| members_of_zone(group) }

  protect(on: :destroy) do
    self.cultivable_zones.any?
  end

  # return the work_number of LandParcelClusters if exist for a CultivableLAndParcel
  def clusters_work_number(viewed_at = nil)
    numbers = []
    groups = self.groups
    for group in groups
      if group.is_a?(LandParcelCluster)
        numbers << group.work_number
      end
    end
    if numbers.count > 0
      numbers.to_sentence
    else
      return nil
    end
  end

end

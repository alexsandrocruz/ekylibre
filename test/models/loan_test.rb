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
# == Table: loans
#
#  accounted_at         :datetime
#  amount               :decimal(19, 4)   not null
#  cash_id              :integer          not null
#  created_at           :datetime         not null
#  creator_id           :integer
#  currency             :string           not null
#  id                   :integer          not null, primary key
#  insurance_percentage :decimal(19, 4)   not null
#  interest_percentage  :decimal(19, 4)   not null
#  journal_entry_id     :integer
#  lender_id            :integer          not null
#  lock_version         :integer          default(0), not null
#  name                 :string           not null
#  repayment_duration   :integer          not null
#  repayment_method     :string           not null
#  repayment_period     :string           not null
#  shift_duration       :integer          default(0), not null
#  shift_method         :string
#  started_on           :date             not null
#  updated_at           :datetime         not null
#  updater_id           :integer
#
require 'test_helper'

class LoanTest < ActiveSupport::TestCase
  test_fixtures

  test "something cool" do
    # assert_equal 2, Loan.count
  end

end

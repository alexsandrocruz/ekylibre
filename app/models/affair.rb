# = Informations
#
# == License
#
# Ekylibre - Simple ERP
# Copyright (C) 2009-2012 Brice Texier, Thibaud Merigon
# Copyright (C) 2012-2014 Brice Texier, David Joulin
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
# == Table: affairs
#
#  accounted_at     :datetime
#  closed           :boolean          not null
#  closed_at        :datetime
#  created_at       :datetime         not null
#  creator_id       :integer
#  credit           :decimal(19, 4)   default(0.0), not null
#  currency         :string(3)        not null
#  deals_count      :integer          default(0), not null
#  debit            :decimal(19, 4)   default(0.0), not null
#  id               :integer          not null, primary key
#  journal_entry_id :integer
#  lock_version     :integer          default(0), not null
#  third_id         :integer          not null
#  third_role       :string(255)      not null
#  updated_at       :datetime         not null
#  updater_id       :integer
#

# Where to put amounts. The point of view is us
#       Deal      |  Debit  |  Credit |
# Sale            |         |    X    |
# SaleCredit      |    X    |         |
# Purchase        |    X    |         |
# PurchaseCredit  |         |    X    |
# IncomingPayment |    X    |         |
# OutgoingPayment |         |    X    |
# ProfitGap       |    X    |         |
# LossGap         |         |    X    |
# Transfer        |         |    X    |
#
class Affair < Ekylibre::Record::Base
  AFFAIRABLE_TYPES = %w(Gap Sale Purchase IncomingPayment OutgoingPayment Transfer).freeze
  AFFAIRABLE_MODELS = AFFAIRABLE_TYPES.map(&:underscore).freeze
  enumerize :third_role, in: [:client, :supplier], predicates: true
  belongs_to :third, class_name: "Entity"
  belongs_to :journal_entry
  has_many :gaps,              inverse_of: :affair, dependent: :nullify
  has_many :sales,             inverse_of: :affair, dependent: :nullify
  has_many :purchases,         inverse_of: :affair, dependent: :nullify
  has_many :incoming_payments, inverse_of: :affair, dependent: :nullify
  has_many :outgoing_payments, inverse_of: :affair, dependent: :nullify
  has_many :transfers,         inverse_of: :affair, dependent: :nullify
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_numericality_of :credit, :debit, allow_nil: true
  validates_length_of :currency, allow_nil: true, maximum: 3
  validates_length_of :third_role, allow_nil: true, maximum: 255
  validates_inclusion_of :closed, in: [true, false]
  validates_presence_of :credit, :currency, :debit, :third, :third_role
  #]VALIDATORS]
  validates_inclusion_of :third_role, in: self.third_role.values

  before_validation do
    deals = self.deals
    self.debit, self.credit, self.deals_count = 0, 0, deals.count
    for deal in deals
      self.debit  += deal.deal_debit_amount
      self.credit += deal.deal_credit_amount
    end
    # Check state
    if self.credit == self.debit # and self.debit != 0
      self.closed = true
      self.closed_at = Time.now
    else
      self.closed = false
      self.closed_at = nil
    end
  end

  # after_save do
  #   if self.deals.size.zero? and !self.journal_entry
  #     self.destroy
  #   end
  # end

  bookkeep do |b|
    label = tc(:bookkeep)
    all_deals = self.deals
    thirds = all_deals.inject({}) do |hash, deal|
      if third = deal.deal_third
        # account = third.account(deal.class.affairable_options[:third])
        account = third.account(deal.deal_third_role.to_sym)
        hash[account.id] ||= 0
        hash[account.id] += deal.deal_debit_amount - deal.deal_credit_amount
      end
      hash
    end.delete_if{|k, v| v.zero?}
    b.journal_entry(Journal.used_for_affairs, printed_on: (all_deals.last ? all_deals.last.dealt_on : Date.today), :if => (self.debit == self.credit and !thirds.empty?)) do |entry|
      for account_id, amount in thirds
        entry.add_debit(label, account_id, amount)
      end
    end
  end


  # Removes empty affairs in the whole table
  def self.clean_deads
    self.where("journal_entry_id NOT IN (SELECT id FROM #{connection.quote_table_name(:journal_entries)})" + AFFAIRABLE_TYPES.collect do |type|
                 model = type.constantize
                 " AND id NOT IN (SELECT #{model.reflections[:affair].foreign_key} FROM #{connection.quote_table_name(model.table_name)})"
               end.join).delete_all
  end

  # Returns the remaining balance of the affair
  # Positive result is a profit
  # A contrario, negative result is a loss
  def balance
    self.debit - self.credit
  end

  # Reload and save! affair to force counts and sums computation
  def refresh!
    self.reload
    self.save!
  end

  # Returns if the affair is bad for us...
  def losing?
    self.debit < self.credit
  end

  # Adds a gap to close the affair
  def finish(distribution = nil)
    balance = self.balance.abs
    return false if balance.zero?
    thirds = self.thirds
    if distribution.nil?
      distribution = self.thirds_distribution
    end
    if distribution.values.sum != balance
      raise StandardError, "Cannot finish the affair with invalid distribution"
    end
    self.class.transaction do
      for third in thirds
        attributes = {affair: self, amount: balance, currency: self.currency, entity: self.third, entity_role: self.third_role, direction: (losing? ? :profit : :loss), items: []}
        self.tax_items_for(third, distribution[third.id], !losing?).each_with_index do |item, index|
          item[:pretax_amount] = (item[:tax] ? item[:tax].pretax_amount_of(item[:amount]) : item[:amount])
          item[:currency] = self.currency
          attributes[:items] << GapItem.new(item)
        end
        # puts attributes.inspect
        Gap.create!(attributes)
      end
      self.refresh!
    end
    return true
  end

  # Returns heterogen list of deals of the affair
  def deals
    return (self.gaps.to_a +
            self.sales.to_a +
            self.purchases.to_a +
            self.incoming_payments.to_a +
            self.outgoing_payments.to_a +
            self.transfers.to_a).compact.sort do |a, b|
      a.dealt_on <=> b.dealt_on
    end
  end

  # Returns deals of the given third
  def deals_of(third)
    return deals.select do |deal|
      deal.deal_third == third
    end
  end

  # Returns all associated thirds of the affair
  def thirds
    return self.deals.map(&:deal_third).uniq
  end

  # Returns a hash with each amount for each third
  # Amounts are always positive although it'a loss or a profit
  # In case of a loss, credits are greater than debits. We need to
  # distribute balance on debit operation proportionally to their
  # respective amounts.
  def thirds_distribution(mode = :equity)
    balance = (self.debit - self.credit).abs
    tendency = (self.debit > self.credit ? :debit : :credit)
    # balance = (tendency == :debit ? self.debit : self.credit)
    tendency_method = "deal_#{tendency}?".to_sym
    amount_method   = "deal_#{tendency}_amount".to_sym
    deals = self.deals.select(&tendency_method)
    amount = deals.map(&amount_method).sum
    thirds = self.thirds
    if mode == :equality
      distribution = thirds.inject({}) do |hash, third|
        hash[third.id] = (balance / thirds.size).round(currency_precision)
        hash
      end
    else
      distribution = thirds.inject({}) do |hash, third|
        third_amount = deals.select do |deal|
          deal.deal_third == third
        end.map(&amount_method).sum
        hash[third.id] = (balance * third_amount / amount).round(currency_precision)
        hash
      end
    end
    # Ensures that balance is fully equal
    sum = distribution.values.sum
    unless sum != balance
      distribution[distribution.keys.last] += (balance - sum)
    end
    return distribution
  end

  # Globalizes taxes of deals and returns an array of hash per tax
  # It uses deal_taxes method of deals which produces summarized list
  # of taxes.
  # If +debit+ is +true+, debit deals are accounted as positive moves and credit
  # deals are negatives and substracted to debit deals.
  def tax_items_for(third, amount, debit = false)
    totals = {}
    for deal in self.deals_of(third)
      # puts "-" * 200
      # puts deal.inspect
      # puts deal.deal_taxes(debit)
      for total in deal.deal_taxes(debit)
        tax_id = total[:tax] ? total[:tax].id : :none
        totals[tax_id] ||= {amount: 0.0, tax: total[:tax]}
        totals[tax_id][:amount] += total[:amount]
      end
    end
    raise totals.inspect
    # Proratize amount against  tax submitted amounts
    total_amount = totals.values.collect{|t| t[:amount] }.sum
    amounts = totals.values.collect do |total|
      {tax: total[:tax], amount: (amount * (total[:amount] / total_amount)).round(currency_precision)}
    end
    # Ensures no needed cents are forgotten or added
    sum = amounts.collect{|t| t[:amount] }.sum
    unless sum != amount
      amounts[-1][:amount] += (amount - sum)
    end
    return amounts
  end

  # Returns the currency precision to use in affair
  def currency_precision(default = 2)
    FinancialYear.at.currency_precision || default
  end


end
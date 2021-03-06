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
# == Table: financial_years
#
#  closed                :boolean          default(FALSE), not null
#  code                  :string           not null
#  created_at            :datetime         not null
#  creator_id            :integer
#  currency              :string           not null
#  currency_precision    :integer
#  id                    :integer          not null, primary key
#  last_journal_entry_id :integer
#  lock_version          :integer          default(0), not null
#  started_on            :date             not null
#  stopped_on            :date             not null
#  updated_at            :datetime         not null
#  updater_id            :integer
#


class FinancialYear < Ekylibre::Record::Base
  attr_readonly :currency
  belongs_to :last_journal_entry, class_name: "JournalEntry"
  has_many :account_balances, class_name: "AccountBalance", foreign_key: :financial_year_id, dependent: :delete_all
  has_many :fixed_asset_depreciations, class_name: "FixedAssetDepreciation"
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_date :started_on, :stopped_on, allow_blank: true, on_or_after: Date.civil(1, 1, 1)
  validates_numericality_of :currency_precision, allow_nil: true, only_integer: true
  validates_inclusion_of :closed, in: [true, false]
  validates_presence_of :code, :currency, :started_on, :stopped_on
  #]VALIDATORS]
  validates_length_of :currency, allow_nil: true, maximum: 3
  validates_length_of :code, allow_nil: true, maximum: 20
  validates_uniqueness_of :code
  validates_presence_of :currency

  # This order must be the natural order
  # It permit to find the first and the last financial year
  scope :currents,  -> { where(closed: false).reorder(:started_on) }
  scope :closables, -> { where(closed: false).where("stopped_on < ?", Time.now).reorder(:started_on).limit(1) }

  class << self

    # Find or create if possible the requested financial year for the searched date
    def at(searched_at = Time.now)
      searched_on = searched_at.to_date
      unless year = self.where("? BETWEEN started_on AND stopped_on", searched_on).order(started_on: :desc).limit(1).first
        # First
        unless first = self.first_of_all
          started_on = Date.today
          first = self.create!(started_on: started_on, stopped_on: (started_on >> 11).end_of_month)
        end
        return nil if first.started_on > searched_on

        # Next years
        other = first
        while searched_on > other.stopped_on
          other = other.find_or_create_next!
        end
        return other
      end
      return year
    end

    def first_of_all
      self.reorder(:started_on).first
    end

    def current
      self.currents.first
    end

    def closable
      self.closables.first
    end

    # Returns the date of the last closure if any
    def last_closure
      if year = self.where(closed: true).reorder(started_on: :desc).first
        return year.stopped_on
      end
      return nil
    end

  end

  before_validation do
    self.currency ||= Preference[:currency]
    if ref = Nomen::Currencies.find(self.currency)
      self.currency_precision ||= ref.precision
    end
    # self.started_on = self.started_on.beginning_of_day if self.started_on
    self.stopped_on = (self.started_on + 11.months).end_of_month if self.stopped_on.blank? and self.started_on
    # self.stopped_on = self.stopped_on.end_of_month unless self.stopped_on.blank?
    if self.started_on and self.stopped_on and code.blank?
      self.code = self.default_code
    end
    self.code.upper!
    while self.class.where(code: self.code).where.not(id: self.id || 0).any? do
      self.code.succ!
    end
  end

  validate do
    unless self.stopped_on.blank? or self.started_on.blank?
      errors.add(:stopped_on, :end_of_month) unless self.stopped_on == self.stopped_on.end_of_month
      errors.add(:stopped_on, :posterior, to: self.started_on.l) unless self.started_on < self.stopped_on
      # If some financial years are already present
      if self.others.any?
        errors.add(:started_on, :overlap) if self.others.where("? BETWEEN started_on AND stopped_on", self.started_on).any?
        errors.add(:stopped_on, :overlap) if self.others.where("? BETWEEN started_on AND stopped_on", self.stopped_on).any?
      end
    end
  end

  def journal_entries(conditions=nil)
    JournalEntry.where(printed_on: self.started_on..self.stopped_on).where(conditions.nil? ? true : conditions)
  end

  def name
    self.code
  end

  def default_code
    tc("code." + (self.started_on.year != self.stopped_on.year ? "double" : "single"), first_year: self.started_on.year, second_year: self.stopped_on.year)
  end

  # tests if the financial_year can be closed.
  def closable?(noticed_on=nil)
    noticed_on ||= Date.today
    return false if self.closed
    if previous = self.previous
      return false if self.previous.closable?
    end
    return false unless self.journal_entries("debit != credit").empty?
    return (self.stopped_on < noticed_on)
  end


  def closures(noticed_on=nil)
    noticed_on ||= Date.today
    array, first_year = [], self.class.order("started_on").first
    if (first_year.nil? or first_year == self) and self.class.count <= 1
      date = self.started_on.end_of_month
      while date < noticed_on
        array << date
        date = (date+1).end_of_month
      end
    else
      array << self.stopped_on
    end
    return array
  end


  # When a financial year is closed,.all the matching journals are closed too.
  def close(to_close_on=nil, options={})
    return false unless self.closable?

    to_close_on ||= self.stopped_on

    ActiveRecord::Base.transaction do
      # Close all journals to the
      for journal in Journal.where("closed_on < ?", to_close_on)
        raise "Journal #{journal.name} cannot be closed on #{to_close_on}" unless journal.close!(to_close_on)
      end

      # Close year
      self.update_attributes(stopped_on: to_close_on, closed: true)

      # Compute balance of closed year
      self.compute_balances!

      # Create first entry of the new year
      if journal = Journal.find_by(id: options[:journal_id].to_i)

        if self.account_balances.any?
          entry = journal.entries.create!(printed_on: to_close_on+1, currency: journal.currency)
          result   = 0
          profit   = Account.find_in_chart(:financial_year_result_profit)
          losses   = Account.find_in_chart(:financial_year_result_loss)
          expenses = Account.find_in_chart(:expenses)
          revenues = Account.find_in_chart(:revenues)

          for balance in self.account_balances.joins(:account).order("number")
            if balance.account.number.to_s.match(/^(#{expenses.number}|#{revenues.number})/)
              result += balance.balance
            elsif balance.balance != 0
              # TODO: Use currencies properly in account_balances !
              entry.items.create!(account_id: balance.account_id, name: balance.account.name, real_debit: balance.balance_debit, real_credit: balance.balance_credit)
            end
          end

          if result > 0
            entry.items.create!(account_id: losses.id, name: losses.name, real_debit: result, real_credit: 0.0)
          elsif result < 0
            entry.items.create!(account_id: profit.id, name: profit.name, real_debit: 0.0, real_credit: result.abs)
          end

        end
      end
    end
    return true
  end

  # this method returns the previous financial_year by default.
  def previous
    return self.class.find_by(stopped_on: self.started_on - 1)
  end

  # this method returns the next financial_year by default.
  def next
    return self.class.find_by(started_on: self.stopped_on + 1)
  end

  # Find or create the next financial year based on the date of the current
  def find_or_create_next!
    unless year = self.next
      year = self.class.create!(started_on: self.stopped_on + 1, stopped_on: self.stopped_on >> 12, currency: self.currency)
    end
    return year
  end


  # Computes the value of list of accounts in a String
  # 123 will take.all accounts 123*
  # ^456 will remove.all accounts 456*
  # 789X will compute the balance although result is negative
  def balance(accounts, credit = false)
    normals, excepts, negatives, forceds = ["(XD)"], [], [], []
    for prefix in accounts.strip.split(/\s*[\,\s]+\s*/)
      code = prefix.gsub(/(^(\-|\^)|[CDX]+$)/, '')
      excepts   << code if prefix.match(/^\^\d+$/)
      negatives << code if prefix.match(/^\-\d+/)
      forceds   << code if prefix.match(/^\-?\d+[CDX]$/)
      normals   << code if prefix.match(/^\-?\d+[CDX]?$/)
    end

    balance = FinancialYear.balance_expr(credit)
    if forceds.size > 0 or negatives.size > 0
      forceds_and_negatives = forceds & negatives
      balance  = "CASE"
      balance << " WHEN "+forceds_and_negatives.sort.collect{|c| "a.number LIKE '#{c}%'"}.join(" OR ")+" THEN -#{FinancialYear.balance_expr(!credit, :forced => true)}" if forceds_and_negatives.size > 0
      balance << " WHEN "+forceds.collect{|c| "a.number LIKE '#{c}%'"}.join(" OR ")+" THEN #{FinancialYear.balance_expr(credit, :forced => true)}" if forceds.size > 0
      balance << " WHEN "+negatives.sort.collect{|c| "a.number LIKE '#{c}%'"}.join(" OR ")+" THEN -#{FinancialYear.balance_expr(!credit)}" if negatives.size > 0
      balance << " ELSE #{FinancialYear.balance_expr(credit)} END"
    end

    query  = "SELECT sum(#{balance}) AS balance FROM #{AccountBalance.table_name} AS ab JOIN #{Account.table_name} AS a ON (a.id=ab.account_id) WHERE ab.financial_year_id=#{self.id}"
    query << " AND ("+normals.sort.collect{|c| "a.number LIKE '#{c}%'"}.join(" OR ")+")"
    query << " AND NOT ("+excepts.sort.collect{|c| "a.number LIKE '#{c}%'"}.join(" OR ")+")" if excepts.size > 0
    balance = ActiveRecord::Base.connection.select_value(query)
    return (balance.blank? ? nil : balance.to_d)
  end

  # Computes and formats debit balance for an account regexp
  # Use I18n to produce string
  def debit_balance(accounts)
    if value = self.balance(accounts, false)
      return value.l(currency: self.currency)
    end
    return nil
  end

  # Computes and formats credit balance for an account regexp
  # Use I18n to produce string
  def credit_balance(accounts)
    if value = self.balance(accounts, true)
      return value.l(currency: self.currency)
    end
    return nil
  end


  def self.balance_expr(credit = false, options = {})
    columns = [:debit, :credit]
    columns.reverse! if credit
    prefix = (options[:record] ? options.delete(:record).to_s + "." : "") + "local_"
    if options[:forced]
      return "(#{prefix}#{columns[0]} - #{prefix}#{columns[1]})"
    else
      return "(CASE WHEN #{prefix}#{columns[0]} > #{prefix}#{columns[1]} THEN #{prefix}#{columns[0]} - #{prefix}#{columns[1]} ELSE 0 END)"
    end
  end



  # Re-create all account_balances record for the financial year
  def compute_balances!
    results = ActiveRecord::Base.connection.select_all("SELECT account_id, sum(debit) AS debit, sum(credit) AS credit, count(id) AS count FROM #{JournalEntryItem.table_name} WHERE state != 'draft' AND printed_on BETWEEN #{self.class.connection.quote(self.started_on)} AND #{self.class.connection.quote(self.stopped_on)} GROUP BY account_id")
    self.account_balances.clear
    results.each do |result|
      self.account_balances.create!(account_id: result["account_id"].to_i, local_count: result["count"].to_i, local_credit: result["credit"].to_f, local_debit: result["debit"].to_f, currency: self.currency)
    end
    return self
  end

  # Generate last journal entry with financial assets depreciations (option.ally)
  def generate_last_journal_entry(options = {})
    unless self.last_journal_entry
      self.create_last_journal_entry!(printed_on: self.stopped_on, journal_id: options[:journal_id])
    end

    # Empty journal entry
    self.last_journal_entry.items.clear

    if options[:fixed_assets_depreciations]
      for depreciation in self.fixed_asset_depreciations.includes(:fixed_asset)
        name = tc(:bookkeep, resource: FixedAsset.model_name.human, number: depreciation.fixed_asset.number, name: depreciation.fixed_asset.name, position: depreciation.position, total: depreciation.fixed_asset.depreciations.count)
        # Charges
        self.last_journal_entry.add_debit(name, depreciation.fixed_asset.expenses_account, depreciation.amount)
        # Allocation
        self.last_journal_entry.add_credit(name, depreciation.fixed_asset.allocation_account, depreciation.amount)
        depreciation.update_attributes(:journal_entry_id => self.last_journal_entry.id)
      end
    end
    return self
  end

end

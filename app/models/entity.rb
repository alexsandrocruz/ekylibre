# == Schema Information
# Schema version: 20090223113550
#
# Table name: entities
#
#  id                    :integer       not null, primary key
#  nature_id             :integer       not null
#  language_id           :integer       not null
#  name                  :string(255)   not null
#  first_name            :string(255)   
#  full_name             :string(255)   not null
#  code                  :string(16)    
#  active                :boolean       default(TRUE), not null
#  born_on               :date          
#  dead_on               :date          
#  ean13                 :string(13)    
#  soundex               :string(4)     
#  website               :string(255)   
#  client                :boolean       not null
#  supplier              :boolean       not null
#  company_id            :integer       not null
#  created_at            :datetime      not null
#  updated_at            :datetime      not null
#  created_by            :integer       
#  updated_by            :integer       
#  lock_version          :integer       default(0), not null
#  client_account_id     :integer       
#  supplier_account_id   :integer       
#  vat_submissive        :boolean       default(TRUE), not null
#  reflation_submissive  :boolean       not null
#  deliveries_conditions :string(60)    
#  discount_rate         :decimal(8, 2) 
#  reduction_rate        :decimal(8, 2) 
#  comment               :text          
#  excise                :string(15)    
#  vat_number            :string(15)    
#  country               :string(2)     
#  payments_number       :integer       
#  employee_id           :integer       
#

class Entity < ActiveRecord::Base
  attr_readonly :company_id
  
 
  #has_many :contact
  def before_validation
    #raise Exception.new self.inspect
    self.soundex = self.name.soundex2
    self.first_name = self.first_name.to_s.strip
    self.name = self.name.to_s.strip
    unless self.nature.nil?
      self.first_name = '' unless self.nature.physical
    end
    self.full_name = (self.name.to_s+" "+self.first_name.to_s).strip
    
    self.code = self.full_name.codeize if self.code.blank?
    self.code = self.code[0..15]
    #    while Entity.find(:first, :conditions=>["company_id=? AND code=? AND id!=?",self.company_id, self.code, self.id||0])
    #      self.code.succ!
    #    end

    
    #self.active = false  unless self.dead_on.blank?
  end
  
  
  def validate
    if self.nature
      #raise Exception.new self.nature.in_name.inspect
      if self.nature.in_name
        errors.add(:name, tc(:error_missing_title,:title=>self.nature.abbreviation)) unless self.name.match(/( |^)#{self.nature.abbreviation}( |$)/i)
      end
    end
  end
  
end 

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  pay_customer default_payment_processor: :fake_processor, allow_fake: true
end

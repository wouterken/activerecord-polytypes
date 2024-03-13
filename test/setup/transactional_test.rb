class TransactionalTest < Minitest::Test
  def around
    ActiveRecord::Base.transaction do
      yield
      raise ActiveRecord::Rollback
    end
  end
end

require 'spec_helper'

describe Arenai do
  specify '#find' do
    assert { Author.find(1).name == 'matz' }
  end

  specify '#all' do
    assert { Author.all.to_a.map(&:name) == %w(matz keiju takahashim aamine nari) }
  end

  specify '#where(String)' do
    assert { Author.where('1=1').to_a.map(&:name) == %w(matz keiju takahashim aamine nari) }
  end

  specify '#where(String)' do
    assert { Author.where("name like '%m%'").to_a.map(&:name) == %w(matz takahashim aamine) }
  end

  specify '#where(String valued Hash)' do
    assert { Author.where(name: 'takahashim').to_a.map(&:name) == %w(takahashim) }
  end

  specify '#where(Fixnum valued Hash)' do
    assert { Author.where(id: 1).to_a.map(&:name) == %w(matz) }
  end

  specify '#where(nil valued Hash)' do
    assert { Author.where(email: nil).to_a.map(&:name) == %w(keiju takahashim aamine nari) }
  end

  specify '#where(String + bind_value)' do
    assert { Author.where('name = ?', 'keiju').to_a.map(&:name) == %w(keiju) }
  end

  specify '#where + all' do
    assert { Author.where('1=1').to_a.map(&:name) == %w(matz keiju takahashim aamine nari) }
  end

  specify '#where + where' do
    assert { Author.where('1=1').where(name: 'nari').to_a.map(&:name) == %w(nari) }
  end

  specify '#where(Hash: Array)' do
    assert { Author.where(email: ['matz@ruby-lang.org', 'nobody@example.com']).to_a.map(&:name) == %w(matz) }
  end

  specify '#where + where(Hash: Array)' do
    assert { Author.where("name like '%m%'").where(email: [nil, 'nobody@example.com']).to_a.map(&:name) == %w(takahashim aamine) }
  end

  specify '#where(Hash: Array) + where' do
    assert { Author.where(id: [1, 2, 3, 4]).where("name like '_a%'").to_a.map(&:name) == %w(matz takahashim aamine) }
  end

  specify '#where(AR)' do
    assert { Author.where(id: Author.find(3)).first.id == 3 }
  end
end

require 'rails_helper'

RSpec.describe Concerns::TwitterUser::Persistence do
  subject(:tu) { build(:twitter_user) }

  describe '#put_relations_back' do
    it 'calls #import_relations!' do
      tu.instance_variable_set(:@shaded, {friends: []})
      expect(TwitterUser).to receive(:import_relations!)
      tu.send(:put_relations_back)
    end

    context '#import_relations! raises an exception' do
      before do
        allow(TwitterUser).to receive(:import_relations!).and_raise('import failed')
      end
      it 'calls #destroy' do
        tu.instance_variable_set(:@shaded, {friends: []})
        expect(tu).to receive(:destroy)
        tu.send(:put_relations_back)
      end
    end
  end

  describe '#save' do
    it 'saves all relations' do
      expect(tu.save).to be_truthy
      user = TwitterDB::User.find_by(uid: tu.uid)

      [
        tu.friends.map(&:uid).map(&:to_i),
        tu.tmp_friends.map(&:uid),
        user.friends.map(&:uid),
        tu.friendships.map(&:friend_uid),
        user.friendships.map(&:friend_uid),
      ].combination(2) { |a, b| expect(a).to eq(b) }

      [
        tu.friends.size,
        tu.friends_size,
        user.friends_size
      ].combination(2) { |a, b| expect(a).to eq(b) }

      [
        tu.followers.map(&:uid).map(&:to_i),
        tu.tmp_followers.map(&:uid),
        user.followers.map(&:uid),
        tu.followerships.map(&:follower_uid),
        user.followerships.map(&:follower_uid),
      ].combination(2) { |a, b| expect(a).to eq(b) }

      [
        tu.followers.size,
        tu.followers_size,
        user.followers_size
      ].combination(2) { |a, b| expect(a).to eq(b) }
    end

    context 'it is new record' do
      it 'calls all callback methods' do
        expect(tu).to receive(:push_relations_aside)
        expect(tu).to receive(:put_relations_back)
        expect(tu).to receive(:import_unfriends)
        expect(tu).to receive(:import_unfollowers)
        expect(tu).to receive(:import_twitter_db_users)
        expect(tu).to receive(:import_relationships)
        expect(tu.save).to be_truthy
      end
    end

    context 'it is already persisted' do
      before { tu.save! }
      it 'does not call any callback methods' do
        tu.uid = tu.uid.to_i * 2
        expect(tu).not_to receive(:push_relations_aside)
        expect(tu).not_to receive(:put_relations_back)
        expect(tu).not_to receive(:import_unfriends)
        expect(tu).not_to receive(:import_unfollowers)
        expect(tu).not_to receive(:import_twitter_db_users)
        expect(tu).not_to receive(:import_relationships)
        expect(tu.save).to be_truthy
      end
    end
  end

  describe '#import_relations!' do
    let(:followers) { [build(:follower)] }
    before { tu.save! } # to generate a primary key

    it 'does not call Follower#valid?' do
      followers.each { |f| expect(f).not_to receive(:valid?) }
      expect { TwitterUser.import_relations!(tu.id, :followers, followers) }.to change { Follower.all.size }.by(1)
    end

    context 'with invalid followers' do
      before { followers.each { |f| f.uid = -100 } }
      it 'saves followers' do
        expect { TwitterUser.import_relations!(tu.id, :followers, followers) }.to change { Follower.all.size }.by(1)
      end
    end

    context 'Follower.import raises an exception' do
      before { allow(Follower).to receive(:import).and_raise('import failed') }

      it 'raises an exception' do
        expect { TwitterUser.import_relations!(tu.id, :followers, followers) }.to raise_error(RuntimeError, 'import failed')
      end
    end
  end

  describe '#import_unfriends' do
    let(:users) { tu.friends }
    before do
      tu.save!
      allow(tu).to receive(:calc_removing).and_return(users)
    end

    context 'Unfriendship.all.empty? == true' do
      before { Unfriendship.delete_all }
      it 'saves unfriendships' do
        expect(Unfriendship.all.empty?).to be_truthy
        expect { tu.send(:import_unfriends) }.to change { Unfriendship.all.size }.by(users.size)
      end
    end

    context 'Unfriendship.all.any? == true' do
      let(:num) { 3 }
      before do
        Unfriendship.delete_all
        num.times.each { create(:unfriendship, friend_id: create(:friend, from_id: tu.id).id, from_uid: tu.uid) }
      end
      it 'deletes old unfriendships and saves new unfriendships' do
        expect([Unfriendship.all.size, tu.unfriends.size]).to match_array([num, num])
        expect { tu.send(:import_unfriends) }.to change { Unfriendship.all.size }.by(-(Unfriendship.all.size - users.size))
      end
    end
  end

  describe '#import_unfollowers' do
    let(:users) { tu.followers }
    before do
      tu.save!
      allow(tu).to receive(:calc_removed).and_return(users)
    end

    context 'Unfollowership.all.empty? == true' do
      before { Unfollowership.delete_all }
      it 'saves unfollowerships' do
        expect(Unfollowership.all.empty?).to be_truthy
        expect { tu.send(:import_unfollowers) }.to change { Unfollowership.all.size }.by(users.size)
      end
    end

    context 'Unfollowership.all.any? == true' do
      let(:num) { 3 }
      before do
        Unfollowership.delete_all
        num.times.each { create(:unfollowership, follower_id: create(:follower, from_id: tu.id).id, from_uid: tu.uid) }
      end
      it 'deletes old unfollowerships and saves new unfollowerships' do
        expect([Unfollowership.all.size, tu.unfollowers.size]).to match_array([num, num])
        expect { tu.send(:import_unfollowers) }.to change { Unfollowership.all.size }.by(-(Unfollowership.all.size - users.size))
      end
    end
  end

  describe '#import_twitter_db_users' do
    it 'calls TwitterDB::User.import_from!' do
      expect(TwitterDB::User).to receive(:import_from!).exactly(3).times
      tu.send(:import_twitter_db_users)
    end
  end

  describe '#import_relationships' do
    it 'calls klass.import_from!' do
      expect(TwitterDB::Friendship).to receive(:import_from!)
      expect(Friendship).to receive(:import_from!)
      expect(TwitterDB::Followership).to receive(:import_from!)
      expect(Followership).to receive(:import_from!)
      tu.send(:import_relationships)
    end
  end
end

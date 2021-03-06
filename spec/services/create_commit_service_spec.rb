require 'spec_helper'

describe CreateCommitService do
  let(:service) { CreateCommitService.new }
  let(:project) { FactoryGirl.create(:project) }

  describe :execute do
    context 'valid params' do
      let(:commit) do 
        service.execute(project,
          ref: 'refs/heads/master',
          before: '00000000',
          after: '31das312',
          ci_yaml_file: gitlab_ci_yaml
        ) 
      end

      it { commit.should be_kind_of(Commit) }
      it { commit.should be_valid }
      it { commit.should be_persisted }
      it { commit.should == project.commits.last }
      it { commit.builds.first.should be_kind_of(Build) }
    end

    context "deploy builds" do
      it "calls create_deploy_builds if there are no builds" do
        config = YAML.dump({jobs: [], build_jobs: ["ls"]})
        Commit.any_instance.should_receive(:create_deploy_builds)
        service.execute(project, ref: 'refs/heads/master', before: '00000000', after: '31das312', ci_yaml_file: config)
      end

      it "does not call create_deploy_builds if there is build" do
        config = YAML.dump({jobs: ["ls"], build_jobs: ["ls"]})
        Commit.any_instance.should_not_receive(:create_deploy_builds)
        service.execute(project, ref: 'refs/heads/master', before: '00000000', after: '31das312', ci_yaml_file: config)
      end
    end

    context "skip tag if there is no build for it" do
      it "creates commit if there is appropriate job" do
        result = service.execute(project,
          ref: 'refs/tags/0_1',
          before: '00000000',
          after: '31das312',
          ci_yaml_file: gitlab_ci_yaml
        )
        result.should be_persisted
      end

      it "does not create commit if there is no appropriate job nor deploy job" do
        result = service.execute(project,
          ref: 'refs/tags/0_1',
          before: '00000000',
          after: '31das312',
          ci_yaml_file: YAML.dump({})
        )
        result.should be_false
      end

      it "creates commit if there is no appropriate job but deploy job has right ref setting" do
        config = YAML.dump({deploy_jobs: [{script: "ls", refs: "0_1"}]})

        result = service.execute(project,
          ref: 'refs/heads/0_1',
          before: '00000000',
          after: '31das312',
          ci_yaml_file: config
        )
        result.should be_persisted
      end
    end

    describe :ci_skip? do
      it "skips commit creation if there is [ci skip] tag in commit message" do
        commits = [{message: "some message[ci skip]"}]
        result = service.execute(project,
          ref: 'refs/tags/0_1',
          before: '00000000',
          after: '31das312',
          commits: commits,
          ci_yaml_file: gitlab_ci_yaml
        )
        result.should be_false
      end

      it "does not skips commit creation if there is no [ci skip] tag in commit message" do
        commits = [{message: "some message"}]

        result = service.execute(project,
          ref: 'refs/tags/0_1',
          before: '00000000',
          after: '31das312',
          commits: commits,
          ci_yaml_file: gitlab_ci_yaml
        )
        
        result.should be_persisted
      end
    end
  end
end

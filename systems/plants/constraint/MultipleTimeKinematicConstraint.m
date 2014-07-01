classdef MultipleTimeKinematicConstraint < RigidBodyConstraint
  % A abstract class, that its eval function takes multiple time points as
  % the input, instead of being evluated at a single time.
    
  methods
    function obj = MultipleTimeKinematicConstraint(robot,tspan)
      obj = obj@RigidBodyConstraint(RigidBodyConstraint.MultipleTimeKinematicConstraintCategory,robot,tspan);
    end
    
    function flag = isTimeValid(obj,t)
      n_breaks = size(t,2);
      if(n_breaks <=1)
        error('Drake:WorldFixedPositionConstraint: t must have more than 1 entry');
      end
      flag = t>=obj.tspan(1)&t<=obj.tspan(end);
    end
    
    function tspan = getTspan(obj)
      tspan = obj.tspan;
    end
    
    function [c,dc] = eval(obj,t,kinsol_cell)
      valid_t_idx = obj.isTimeValid(t);
      valid_t = t(valid_t_idx);
      valid_kinsol_cell = kinsol_cell(valid_t_idx);
      nq = obj.robot.getNumDOF();
      if(length(valid_t)>=2)
        num_valid_t = size(valid_t,2);
        [c,dc_valid] = evalValidTime(obj,valid_kinsol_cell);
        nc = obj.getNumConstraint(t);
        dc = zeros(nc,nq,length(t));
        dc_valid = reshape(dc_valid,nc,nq,num_valid_t);
        dc(:,:,valid_t_idx) = dc_valid;
        dc = reshape(dc,nc,nq*length(t));
      else
        c = [];
        dc = [];
      end
    end
    
    function obj = updateRobot(obj,robot)
      obj.robot = robot;
      obj.mex_ptr = updatePtrRigidBodyConstraintmex(obj.mex_ptr,'robot',robot.getMexModelPtr);
    end
    
    function cnstr = generateConstraint(obj,N)
      % generate a FunctionHandleConstraint for postures at all time t
      if(N >= 2)
        [lb,ub] = obj.bounds(N);
        nq = obj.robot.getNumPositions;
        cnstr = {FunctionHandleConstraint(lb,ub,N*nq,@(varargin) obj.evalValidTime(varargin(N+(1:N))))};
        %num_cnstr = obj.getNumConstraint(N);
        %joint_idx = obj.kinematicPathJoints();
        %iCfun = reshape(bsxfun(@times,(1:num_cnstr)',ones(1,length(joint_idx)*N)),[],1);
        %jCvar = reshape(bsxfun(@times,ones(num_cnstr,1),reshape(bsxfun(@plus,nq*((1:N)-1),joint_idx'),1,[])),[],1);
        %cnstr{1} = cnstr{1}.setSparseStructure(iCfun,jCvar);
        %name_str = obj.name(t);
        %cnstr{1} = cnstr{1}.setName(name_str);
      else
        cnstr = {};
      end
    end
    
    function joint_idx = kinematicPathJoints(obj)
      % return the indices of the joints used to evaluate the constraint. The default
      % value is (1:obj.robot.getNumDOF);
      joint_idx = (1:obj.robot.getNumDOF);
    end
  end
  
  methods(Abstract)
    % N is the number of knot points considered by this constraint
    num = getNumConstraint(obj,N);
    [lb,ub] = bounds(obj,N)
    name_str = name(obj,t)
  end
  
  methods(Abstract,Access = protected)
    [c,dc] = evalValidTime(obj,valid_kinsol_cell);
  end
end

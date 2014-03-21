classdef QuasiStaticConstraint<RigidBodyConstraint
% constrain the Center of Mass to lie inside the shrunk support polygon
% @param active            -- A flag, true if the quasiStaticFlag would be active
% @param num_bodies        -- An int, the total number of bodies that have active
%                             ground contact points
% @param bodies            -- An int array of size 1xnum_bodies. The index of each
%                             ground contact body
% @param num_body_pts      -- An int array of size 1xnum_bodies. The number of
%                             active contact points in each body
% @param body_pts          -- A cell array of size 1xnum_bodies. body_pts{i} is a
%                             3xnum_body_pts(i) double array, which is the active
%                             ground contact points in the body frame
% @param robotnum          -- The robotnum to compute CoM. Default is 1
  properties(SetAccess = protected)
    robotnum;
    shrinkFactor
    active;
    num_pts 
    bodies;
    body_pts;
  end
  
  properties(SetAccess = protected, GetAccess = protected)
    nq;
    num_bodies;
    num_body_pts;
    plane_row_idx;
  end
  methods
    function obj = QuasiStaticConstraint(robot,tspan,robotnum)
      if(nargin<3)
        robotnum = 1;
      end
      if(nargin <2)
        tspan = [-inf,inf];
      end
      checkDependency('rigidbodyconstraint_mex');
      ptr = constructPtrRigidBodyConstraintmex(RigidBodyConstraint.QuasiStaticConstraintType,robot.getMexModelPtr,tspan,robotnum);
      obj = obj@RigidBodyConstraint(RigidBodyConstraint.QuasiStaticConstraintCategory,robot,tspan);
      if(~isempty(setdiff(robotnum,1:length(obj.robot.name))))
        error('Drake:QuasiStaticConstraint: robotnum is not accepted');
      end
      obj.robotnum = robotnum;
      obj.nq = robot.getNumDOF;
      obj.shrinkFactor = 0.9;
      obj.active = false;
      obj.num_bodies = 0;
      obj.num_pts = 0;
      obj.bodies = [];
      obj.num_body_pts = [];
      obj.body_pts = {};
      obj.plane_row_idx;
      obj.type = RigidBodyConstraint.QuasiStaticConstraintType;
      obj.mex_ptr = ptr;
    end
    
    function flag = isTimeValid(obj,t)
      if(isempty(t))
        flag = true;
      else
        flag = t>=obj.tspan(1) & t<=obj.tspan(end);
      end
    end
    
    function obj = setActive(obj,flag)
      obj.active = logical(flag);
      obj.mex_ptr = updatePtrRigidBodyConstraintmex(obj.mex_ptr,'active',obj.active);
    end
    
    function num_cnst = getNumConstraint(obj,t)
      if(obj.isTimeValid(t))
        num_cnst = 3;
      else
        num_cnst = 0;
      end
    end
    
    function obj = addContact(obj,varargin)
      % obj.addContact(body1,body1_pts,body2,body2_pts,...,bodyN,bodyN_pts)
      obj.mex_ptr = updatePtrRigidBodyConstraintmex(obj.mex_ptr,'contact',varargin{:});
      i = 1;
      while(i<length(varargin))
        body = varargin{i};
        body_pts = varargin{i+1};
        if(isnumeric(body))
          sizecheck(body,[1,1]);
        elseif(ischar(body))
          body = obj.robot.findLinkInd(body);
        elseif(typecheck(body,'RigidBody'))
          body = obj.robot.findLinkInd(body.linkname);
        else
          error('Drake:QuasiStaticConstraint:Body must be either the link name or the link index');
        end
        body_idx = find(obj.bodies == body);
        if(isempty(body_idx))
          obj.bodies = [obj.bodies body];
          obj.num_bodies = obj.num_bodies+1;
          npts = size(body_pts,2);
          sizecheck(body_pts,[3,npts]);
          obj.body_pts = [obj.body_pts {body_pts}];
          obj.num_body_pts = [obj.num_body_pts npts];
          row_idx = bsxfun(@plus,[1;2;3],3*(0:npts-1));
          obj.plane_row_idx = [obj.plane_row_idx;obj.num_pts*3+reshape(row_idx(1:2,:),[],1)];
          obj.num_pts = obj.num_pts+npts;
        else
          num_body_pts_tmp = size(obj.body_pts{body_idx},2);
          obj.body_pts{body_idx} = (unique([obj.body_pts{body_idx} body_pts]','rows'))';
          obj.num_body_pts(body_idx) = size(obj.body_pts{body_idx},2);
          obj.num_pts = obj.num_pts-num_body_pts_tmp+obj.num_body_pts(body_idx);
          row_idx = reshape((1:3*obj.num_pts),3,obj.num_pts);
          obj.plane_row_idx = reshape(row_idx(1:2,:),[],1);
        end
        i = i+2;
      end
    end
    
    function obj = setShrinkFactor(obj,factor)
      obj.mex_ptr = updatePtrRigidBodyConstraintmex(obj.mex_ptr,'factor',factor);
      typecheck(factor,'double');
      sizecheck(factor,[1,1]);
      if(factor<0)
        error('QuasiStaticConstraint: shrinkFactor should be non negative');
      end
      obj.shrinkFactor = factor;
    end
    
    function [c,dc] = eval(obj,t,kinsol,weights)
      if(obj.isTimeValid(t))
        [c,dc] = obj.evalValidTime(kinsol,weights);
      else
        c = [];
        dc = [];
      end
    end
    
    function [c,dc] = evalValidTime(obj,kinsol,weights)
      [com,dcom] = obj.robot.getCOM(kinsol,obj.robotnum);
      contact_pos = zeros(3,obj.num_pts);
      dcontact_pos = zeros(3*obj.num_pts,obj.nq);
      num_accum_pts = 0;
      for i = 1:obj.num_bodies
        [contact_pos(:,num_accum_pts+(1:obj.num_body_pts(i))),...
          dcontact_pos(3*num_accum_pts+(1:3*obj.num_body_pts(i)),:)] = forwardKin(obj.robot,kinsol,obj.bodies(i),obj.body_pts{i},0);
        num_accum_pts = num_accum_pts+obj.num_body_pts(i);
      end
      plane_contact_pos = contact_pos(1:2,:);
      dplane_contact_pos = dcontact_pos(obj.plane_row_idx,:);
      center_pos = mean(plane_contact_pos,2);
      dcenter_pos = [mean(dplane_contact_pos(1:2:end,:),1);mean(dplane_contact_pos(2:2:end,:),1)];
      support_pos = plane_contact_pos*obj.shrinkFactor+bsxfun(@times,center_pos*(1-obj.shrinkFactor),ones(1,obj.num_pts));
      dsupport_pos = dplane_contact_pos*obj.shrinkFactor+repmat(dcenter_pos*(1-obj.shrinkFactor),obj.num_pts,1);
      c = com(1:2,:)-support_pos*weights;
      dc = [dcom(1:2,:)-[weights'*dsupport_pos(1:2:end,:);weights'*dsupport_pos(2:2:end,:)] -support_pos];
    end
    
    function flag = checkConstraint(obj,kinsol)
      com = obj.robot.getCOM(kinsol);
      contact_pos = zeros(3,obj.num_pts);
      num_accum_pts = 0;
      for i = 1:obj.num_bodies
        contact_pos(:,num_accum_pts+(1:obj.num_body_pts(i))) = forwardKin(obj.robot,kinsol,obj.bodies(i),obj.body_pts{i},0);
        num_accum_pts = num_accum_pts+obj.num_body_pts(i);
      end
      center_pos = mean(contact_pos,2);
      shrinkFactor = obj.shrinkFactor+1e-4;
      shrink_vertices = contact_pos*shrinkFactor+repmat(center_pos*(1-shrinkFactor),1,num_accum_pts);
      problem.d = com(1:2);
      problem.C = shrink_vertices(1:2,:);
      problem.x0 = 1/obj.num_pts*ones(obj.num_pts,1);
      problem.Aeq = ones(1,obj.num_pts);
      problem.beq = 1;
      problem.lb = zeros(1,obj.num_pts);
      problem.ub = ones(1,obj.num_pts);
      problem.solver = 'lsqlin';
      problem.options = optimset('LargeScale','off','Display','off');
      [weights,resnorm,~,exitflag] = lsqlin(problem);
      flag = resnorm<1e-6;
    end
    
    function [lb,ub] = bounds(obj,t)
      if(obj.isTimeValid(t))
        lb = [0;0];
        ub = [0;0];
      else
        lb = [];
        ub = [];
      end
    end
    function name_str = name(obj,t)
      if(obj.isTimeValid(t))
        if(isempty(t))
          name_str = {sprintf('QuasiStaticConstraint x');sprintf('QuasiStaticConstraint y')};
        else
          name_str = {sprintf('QuasiStaticConstraint x at time %10.4f',t);sprintf('QuasiStaticConstraint y at time %10.4f',t)};
        end
      else
        name_str = [];
      end
    end
    
    function obj = updateRobotnum(obj,robotnum)
      if(~isempty(setdiff(robotnum,1:length(obj.robot.name))))
        error('Drake:QuasiStaticConstraint: robotnum is not accepted');
      end
      obj.robotnum = robotnum;
      obj.mex_ptr = updatePtrRigidBodyConstraintmex(obj.mex_ptr,'robotnum',robotnum);
    end
    
    function obj = updateRobot(obj,robot)
      obj.robot = robot;
      obj.nq = obj.robot.getNumDOF();
      obj.mex_ptr = updatePtrRigidBodyConstraintmex(obj.mex_ptr,'robot',obj.robot.getMexModelPtr);
    end
    
    function cnstr = generateConstraint(obj,t)
      % generate a NonlinearConstraint, a LinearConstraint and a BoundingBoxConstraint if the time is valid
      % @retval cnstr  -- A NonlinearConstraint enforcing the CoM on xy-plane matches
      % witht the weighted sum of the shrunk vertices; A LinearConstraint on the weighted
      % sum only, and a BoundingBoxConstraint on the weighted sum only
      if(obj.isTimeValid(t))
        name_str = obj.name(t);
        cnstr = {NonlinearConstraint([0;0],[0;0],obj.nq+obj.num_pts,@obj.evalValidTime),...
          LinearConstraint(1,1,ones(1,obj.num_pts)),...
          BoundingBoxConstraint(zeros(obj.num_pts,1),ones(obj.num_pts,1))};
        cnstr{1} = cnstr{1}.setName(name_str(1:2));
        t_str = '';
        if(~isempty(t))
          t_str = sprintf('at time %5.2f',t);
        end
        cnstr{2} = cnstr{2}.setName({sprintf('QuasiStaticConstraint sum of weights %s',t_str)});
      else
        cnstr = {};
      end
    end
    
  end
 
end

classdef CurlCurl < handle
    % ofem.CurlCurl implements the assemble routines and the interface for
    % solving an electromagnetic problem of the form
    
    
    properties(Access=protected)
        mesh; % The mesh
        fe  ; % The finite element
        qr  ; % The quadrature rule
		feLG; % P1 element for the generalized Lorenz Gauge
		qrLG;
    end

    methods(Access=protected,Static)

        %%
        function S=stiffness(A,sign,Dk,detD,dphi,el,ed,fa,el2ed,el2fa,w,l,co)
        %stiffness returns the stiffness matrix.
        %
        % S=stiffness(DinvT,detD,dphi,w,el,co) returns the stiffness matrix
        % for the local set of elements specified through el. co are the
        % coordinates of the mesh. DinvT and detD are, respectively, the
        % transposed inverse of the Jacobian of Phi and the Jacobians'
        % determinants, per element, where Phi denotes the diffeomorphism
        % taking the reference element to the global one. E.g., for the
        % i-th element DinvT(:,:,i) is the i-th Jacobians' transposed
        % inverse and detD(1,1,i) the determinant. See
        % ofem.mesh.jacobian_data on how these quantities are organized.
        % The computation is carried out in terms of a quadrature rule.
        % The gradients dphi at quadrature points and weights w of the
        % quadrature rule are expected as returned by
        % ofem.finiteelement.dphi. The quadrature points can be queried
        % from, e.g., ofem.gaussianquadrature.data.
        %
        % See also ofem.mesh.jacobian_data, ofem.finiteelement.phi,
        % ofem.finiteelement.dphi, ofem.quassianquadrature.data
        %
            Ns = size(dphi,2);
            Nq = size(w   ,2);
            Ne = size(el  ,1);
            Nc = 2*size(ed,1)+2*size(fa,1);
			Nl = 4;
            
            S=ofem.matrixarray(zeros(Ns,Ns,Ne));

			if isa(A,'function_handle')
				elco = reshape(co(:,:,el(:,1:Nl)'),[],Nl,Ne);
				for q=1:Nq
					X = elco*(l(q,:)');
					dphii = Dk*(dphi(:,:).*sign);
					S = S+(dphii'*A(X)*dphii);
				end
			else
				for q=1:Nq
					dphii = Dk*(dphi(:,:,q).*sign);
					S = S+(dphii'*A*dphii);
				end
			end

            S=S*(1./abs(detD));

            JE = repmat(1:6,6,1);
			JF = repmat(1:4,4,1);
            IE = el2ed(:,JE')';
			IF = el2fa(:,JF')';
			I = [IE;IE+size(ed,1);IF+2*size(ed,1);IF+2*size(ed,1)+size(fa,1)];
            J = el2ed(:,J )';

            S = sparse(I(:),J(:),S(:),Nc,Nc);
        end


        %%(opt.b{i},opt.v,DinvTLoc,DkLoc,phi,dphi,w,elemsLoc,obj.mesh.ed,el2edLoc)
        function D=damping(b,v,sign,detD,DinvT,Dk,phi,dphi,w,el,ed,el2ed)
        %DAMPING returns the damping matrix.
        %
        % D=damping(b,DinvT,detD,phi,dphi,w,el,co) returns the damping
        % matrix for the local set of elements specified through el. co are
        % the coordinates of the mesh. DinvT and detD are, respectively,
        % the transposed inverse of the Jacobian of Phi and the Jacobians'
        % determinants, per element, where Phi denotes the diffeomorphism
        % taking the reference element to the global one. E.g., for the
        % i-th element DinvT(:,:,i) is the i-th Jacobians' transposed
        % inverse and detD(1,1,i) the determinant. See
        % ofem.mesh.jacobian_data on how these quantities are organized.
        % phi and dphi contains, respectively, the values of the shape
        % functions and the shape functions' gradients at quadrature
        % points, w carries the quadratures rules' weights.
        % The shape functions phi and the gradients dphi at quadrature
        % points and weights w of the quadrature rule are expected as
        % returned by ofem.finiteelement.phi and ofem.finiteelement.dphi.
        % The quadrature points can be queried from, e.g.,
        % ofem.quassianquadrature.data.
        %
        % See also ofem.mesh.jacobian_data, ofem.finiteelement.phi,
        % ofem.finiteelement.dphi, ofem.quassianquadrature.data
        %
            Nq = size(w   ,1);
            Ns = size(dphi,2);
            Nd = size(dphi,1);
            Ne = size(el  ,1);
            Nc = size(ed  ,1);
			Nl = 4;

            D=ofem.matrixarray(zeros(Ns,Ns,Ne));
            
            vCurlPhi = ofem.matrixarray(zeros(Nd,Ns,Ne));
            
            cPhi = (dphi(:,:).*sign);
            v = ofem.matrixarray(repmat(v,1,1,Ne));
            for i=1:Ns
                vCurlPhi(:,i,:) = cross(v,1./(detD)*(Dk*cPhi(:,i)));
            end

            for q=1:Nq
                D = D + w(q)*(vCurlPhi'*(DinvT*(phi(:,:,q).*sign)));
            end
            
            D = b*D*abs(detD);

            J = repmat(1:Ns,Ns,1);
            I = el2ed(:,J')';
            J = el2ed(:,J )';

            D = sparse(I(:),J(:),D(:),Nc,Nc);
        end


        %%
        function M=mass(c,sign,DinvT,detD,phi,w,el,ed,el2ed,co)
        %MASS returns the mass matrix.
        %
        % M=mass(detD,pipj,el,co) returns the mass matrix for the local set
        % of elements specified through el. co are the coordinates of the
        % mesh. detD is the per element determinant of the Jacobian of the
        % diffeomorphism taking the reference element to the global one.
        % E.g., detD(1,1,i) it the determinant for the i-th element. See
        % ofem.mesh.jacobian_data on how these quantities are organized.
        % pipj is the integral of the reference element over
        % \phi_i\cdot\phi_j, with \phi_k being the k-th basis function. See
        % ofem.finiteelement.phiiphij on how the data is orginized.
        %
        % See also ofem.mesh.jacobian_data, ofem.finiteelement.phiiphij
        %

            Nq = size(w,1);
            Ns = size(phi,2);
            Nc = size(ed,1);
            Ne = size(el,1);
			Nl = 4;
            
            phii = ofem.matrixarray(zeros(6,6,Ne));

			if isa(c,'function_handle')
				elco = reshape(co(:,:,el(:,1:Nl)'),[],Nl,Ne);
				for q=1:Nq
					X = elco*(l(q,:)');
					phii = phii + w(q)*((DinvT*(phi(:,:,q).*sign))'*c(X)*(DinvT*(phi(:,:,q).*sign)));
				end
			else
				for q=1:Nq
					phii = phii + w(q)*((DinvT*(phi(:,:,q).*sign))'*c*(DinvT*(phi(:,:,q).*sign)));
				end
			end
         
            M = (abs(detD))*phii;

            J = repmat(1:Ns,Ns,1);
            I = el2ed(:,J')';
            J = el2ed(:,J )';

            M=sparse(I(:),J(:),M(:),Nc,Nc);
        end


        %%
        function b=volume_force(sign,detD,DinvT,phi,w,l,f,el,co,el2ed,pIdx,Nc)
        %volume_force returns the volume force part of the load vector.
        %
        % b=volume_force(detD,phi,w,l,f,el,co) computes the force in
        % terms of a quadrature rule. w and l are the weights and
        % quadrature points of the rule, respectively. phi contains the
        % values of the shape functions evaluated at the quadrature points
        % and f is a functions handle returning the value of the force
        % distribution at arbitrary points.
        %
        % See also ofem.mesh.jacobian_data, ofem.finiteelement.phi,
        % ofem.quassianquadrature.data
        %
            Nl   = size(l  ,1)+1; % number of barycentric coordinates
            Nq   = size(w  ,1);
            Ne   = size(el ,1);
            l(4,:) = 1-sum(l,1);
            
            % eval at quadrature points
            elco = reshape(co(:,:,el(:,1:Nl)'),[],Nl,Ne);
            

            F    = ofem.matrixarray(zeros(6,1,Ne));

            if(isa(f,'function_handle'))
                for q=1:Nq
                    X = elco*l(:,q);
                    A = f(X);
                    if ~isempty(A)
                        F = F + (w(q)*(DinvT*(phi(:,:,q).*sign))'*A);
                    end
                end
            elseif f==0
                F = ofem.matrixarray(zeros(6,1,Ne));
            else
                f = f(:,:,pIdx);
                phii = ofem.matrixarray(zeros(3,6,Ne));
                for q=1:Nq
                    phii = phii + (w(q)*DinvT*phi(:,:,q).*sign);
                end
                F = phii'*f;
            end

            %F = permute(double(F*detD),[3,2,1]);
            %F = repmat(F,6,1,1);

            F  = F*abs(detD);
            el2ed = el2ed';
            b  = sparse(el2ed(:),1,F(:),Nc,1);
        end


        %%
        function b=pressure(meas,phi,w,l,g,faces,co)
        %pressure returns the pressure-originated part of the load vector.
        %
        % b=pressure(meas,phi,w,l,g,faces,co) computes the pressure
        % originated vector in terms of a quadrature rule. w and l are the
        % weights and quadrature points of the rule, respectively. phi
        % contains the values of the shape functions evaluated at the
        % quadrature points and g is a functions handle returning the
        % pressure at arbitrary points.
        %
        % See also ofem.mesh.jacobian_data, ofem.mesh.neumann,
        % ofem.finiteelement.phi, ofem.quassianquadrature.data
        %
            
            Nl     = size(l  ,2); % number of barycentric coordinates
            Nc     = size(co ,3);
            Nq     = size(w  ,1);
            Ns     = size(phi,1);
            Nf     = size(faces,1);

            % elco*l gives global quadrature points => eval there
            faceco = reshape(co(:,:,faces(:,1:Nl)'),[],Nl,Nf);

            F      = ofem.matrixarray(zeros(1,Ns,Nf));

            for q=1:Nq
                X = faceco*(l(q,:)');
                F = F + g(X)*(w(q)*phi(:,q)');
            end

%             F = permute(double(F*meas),[3,2,1]);

            F     = F*meas;
            faces = faces';
            b     = sparse(faces(:),1,F(:),Nc,1);
        end


        %%
        function b=dirichlet(f,edges,ed,co)
        %dirichlet returns the Dirichlet-originated part of the load vector.
        %
        % b=dirichlet(el,co) computes the Dirichlet-originated vector at
        % the specified faces.
        %
            Ne  = size(ed ,1);
            v = co(:,:,ed(edges,2))-co(:,:,ed(edges,1));
			if isa(f,'function_handle')
				edco = 1/2*co(:,:,ed(edges,2))+1/2*co(:,:,ed(edges,1));
				F = f(edco);
			else
				F = f;
			end
			D = double(squeeze(dot(F,v)));
            b   = sparse(edges,1,D(:),Ne,1);
		end
		
		%%
		function [G,L] = lorenzGauge(chi,eps,sign,detD,DinvT,pipj,dphiLG,phi,wLG,w,co,ed,el,el2ed)
			Ns = size(pipj,1);
            Nc = size(co  ,3);
            
            L = (chi*pipj)*ofem.matrixarray(abs(detD));

            J = repmat(1:Ns,Ns,1);
            I = el(:,J')';
            J = el(:,J )';

            L=sparse(I(:),J(:),L(:),Nc,Nc);
			
			Nq = size(w,1);
            Ns = size(phi,2);
            Nc = size(ed,1);
            Ne = size(el,1);
			
			phii = ofem.matrixarray(zeros(6,4,Ne));
			
			for i=1:size(phi,3)
				phii = phii + w(i)*((DinvT*sign.*phi(:,:,i))' * (DinvT*dphiLG'));
			end
			
			G = phii*eps*abs(detD);
			
			I = repmat(1:6,4,1);
			I = el2ed(:,I');
			J = repmat(1:4,6,1);
			J = el(:,J);
			
			G = sparse(I(:),J(:),G(:),size(ed,1),size(co,3))';
			
		end
    end

    methods
        %%
        function obj=CurlCurl(mesh,fe,qr)
        %elliptic construct the object
        %
        % elliptic(mesh,fe,qr) construct the object from a ofem.mesh mesh,
        % a ofem.finiteelement fe and a quadrature rule qr, e.g.,
        % ofem.gaussianquadrature.
        %
        % see also ofem.mesh, ofem.finiteelement, ofem.gaussianquadrature
        %
            if ~mesh.is_valid()
                error('ofem:elliptic:InvalidArgument', ...
                      'Invalid mesh specified');
            end

            obj.mesh = mesh;
            %obj.mesh.el = sort(obj.mesh.el,2);
			%obj.mesh.el = sortrows(obj.mesh.el);
            obj.mesh.create_edges();
			obj.mesh.create_faces();
            obj.fe   = fe;
            obj.qr   = qr;
		end

		function setLG(obj,feLG,qrLG)
			obj.feLG = feLG;
			obj.qrLG = qrLG;
		end

        %%
        function [asm,info,aux] = assemble(obj,varargin)
        %assemble assembles the desired matrices and load vector.
        %
        % [asm,info,aux]=assemble computes the stiffness matrix assuming
        % A=I, i.e., the equation reduces to Laplaces' equation with
        % homogeneous zero Neumann data on the whole boundary.
        %
        % [asm,info,aux]=assemble(opt), additionally, makes it possible to
        % specify the material and which matrix and/or load vector to
        % compute.
        % opt is expected to be structure with one or more of the follwoing
        % fields:
        %   - opt.A: The matrix-valued function A, assumed to be constant
        %            per element.
        %
        %   - opt.b: The vector-valued function b, assumed to be constant
        %            per element
        %
        %   - opt.c: The scalar-valued function c, assumed to be constant
        %            per element
        %
        %   - opt.S: If equal to 1, compute stiffness matrix
        %
        %   - opt.D: If equal to 1, compute damping matrix
        %
        %   - opt.M: If equal to 1, compute mass matrix
        %
        %   - opt.force: A function handle expected to return the volume
        %            force distribution at arbitrary points
        %
        %   - opt.dirichlet: If provided, is expected to be either a
        %            structure containing the field 'f' and 'idx', or a
        %            cell array each entry of which is the aforesaid
        %            structure. The field 'f' is either a numerical
        %            scalar value or a function handle. The function handle
        %            expects as its only argument the point at which the
        %            function shall be evaluated and must return exactly
        %            one scalar for each evaluation point. The field  'idx'
        %            contains the index into the 'bd' field of the passed
        %            ofem.mesh class describing the boundary part the
        %            'f' field shall be associated with.
        %
        %   - opt.neumann: If provided, is expected to be either a
        %            structure containing the field 'f' and 'idx', or a
        %            cell array each entry of which is the aforesaid
        %            structure. The field 'f' is either a numerical
        %            scalar value or a function handle. The function handle
        %            expects two arguments, the first one is the point at
        %            which to evaluate and the second the outer normal at
        %            this point and must return exactly one scalar for each
        %            evaluation point. The 'idx' contains the index into
        %            the 'bd' field of the passed ofem.mesh class
        %            describing the boundary part the 'f' field shall be
        %            associated with.
        %
        %   - opt.robin: If provided, is expected to be either a
        %            structure containing the field 'alpha', 'f' and 'idx',
        %            or a cell array each entry of which is the aforesaid
        %            structure. The field 'data' is either a numerical
        %            vector of length two or a function handle. The
        %            function handle expects two arguments, the first one
        %            is the point at which to evaluate and the second the
        %            outer normal at this point and must return exactly
        %            one vector of length two for each evaluation point.
        %            The 'idx' contains the index into the 'bd' field of
        %            the passed ofem.mesh class describing the boundary
        %            part the 'alpha' and 'f' fields shall be associated
        %            with.
        %
        % Example: if opt=struct('S',1,'A',[2,0,0;0,1,0;0,0,1]) then only
        % the stiffness matrix is computed, however, the material is
        % isotropic with specified characteristic.
        %
            Np      = size(obj.mesh.parts,2);
            Nc      = size(obj.mesh.ed,1);
            intvol  = 0;
            intface = 0;
            intdiri = 0;

            dim = obj.mesh.dim;

            %% check input
            if nargin==1
                % Laplace equation with homogenous Neumann boundary
                opt=struct('S',1,'D',0,'M',0,'force',0,'A',1,'b',zeros(dim,1),'c',0);
            else
                if nargin>3
                    warning('ofem:elliptic:TooManyArguments',...
                            'I''m expecting at most one argument. I''ll skip the rest of them!');
                end
                opt=varargin{1};

                if ~isstruct(opt)
                    error('ofem:elliptic:InvalidArgument',...
                          'opt is expected to be a structure.');
                end

                %% stiffness
                if ~isfield(opt,'S')
                    opt.S = 0;
                else
                    aux.S = cell(Np,1);
                    if ~isfield(opt,'A')
                        opt.A=1;
                    end
                end

                %% damping
                if ~isfield(opt,'D')
                    opt.D=0;
                else
                    aux.D = cell(Np,1);
                    if ~isfield(opt,'b')
                        %fix
                        opt.b=zeros(dim,1);
                        opt.b(1)= 1;
                    end
                    if ~isfield(opt,'v')
                        opt.v = [0,0,0];
                    end
                end

                %% mass
                if ~isfield(opt,'M')
                    opt.M=0;
                else
                    aux.M = cell(Np,1);
                    if ~isfield(opt,'c')
                        opt.c=1;
                    end
				end
				
				%% Gauge
				if ~isfield(opt,'R')
                    opt.R=0;
                else
                    aux.R = cell(Np,1);
                    if ~isfield(opt,'chi')
                        opt.chi=1;
					end
					if ~isfield(opt,'eps')
                        opt.eps=1;
                    end
				end

                %% volume force
                if ~isfield(opt,'force')
                    opt.force={};
                else
                    aux.force = cell(Np,1);
                end

                %% Dirichlet boundary
                if ~isfield(opt,'dirichlet')
                    opt.dirichlet={};
                    Ndiri=0;
                else
                    if iscell(opt.dirichlet)
                        for k=1:numel(opt.dirichlet)
                            if ~all(isfield(opt.dirichlet{k},{'f','idx'}))
                                error('ofem:elliptic:InvalidArgument',...
                                      'Each cell entry in opt.dirichlet must be a struct containing a ''f'' and a ''idx'' field.');
                            end
                            if isnumeric(opt.dirichlet{k}.f) && ~isscalar(opt.dirichlet{k}.f) && isvector(opt.dirichlet{k}.f) && ~isrow(opt.dirichlet{k}.f)
                                val = opt.dirichlet{k}.f;
                                opt.dirichlet{k}.f = @(X) ofem.matrixarray(val.*ones(1,1,size(X,3)));
                            elseif isa(opt.dirichlet{k}.f,'function_handle')
                            else
                                error('ofem:elliptic:InvalidArgument',...
                                      'The ''f'' entry in opt.dirichlet must either be a column vector of length 3 or a function handle.');
                            end
                        end
                    elseif isstruct(opt.dirichlet) && all(isfield(opt.dirichlet,{'f','idx'}))
                        dirichlet_f   = opt.dirichlet.f  ;
                        dirichlet_idx = opt.dirichlet.idx;
                        
                        if ~isvector(dirichlet_idx)
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''idx'' entry in opt.dirichlet must be a vector.');
                        end
                        
                        if isnumeric(dirichlet_f) && ~isscalar(dirichlet_f) && isvector(dirichlet_f)
                            val = dirichlet_f;
                            dirichlet_f = @(X) ofem.matrixarray(val*ones(1,1,size(X,3)));
                        elseif isa(dirichlet_f,'function_handle')
                        else
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''f'' entry in opt.dirichlet must either be a vector or a function handle.');
                        end
                        
                        opt.dirichlet = cell(numel(dirichlet_idx),1);
                        for k=1:numel(dirichlet_idx)
                            opt.dirichlet{k}.f   = dirichlet_f;
                            opt.dirichlet{k}.idx = dirichlet_idx(k);
                        end
                    else
                        error('ofem:elliptic:InvalidArgument',...
                              'opt.dirichlet must either be a cell array or a structure containing a ''f'' and a ''idx'' field.');
                    end

                    Ndiri         = numel(opt.dirichlet);
                    aux.dirichlet = cell(Ndiri,1);
                    aux.dirichletEdges = cell(Ndiri,1);
                end

                %% Neumann boundary, pressure
                if ~isfield(opt,'neumann')
                    opt.neumann={};
                    Nneu=0;
                else
                    if iscell(opt.neumann)
                        for k=1:numel(opt.neumann)
                            if ~all(isfield(opt.neumann{k},{'f','idx'}))
                                error('ofem:elliptic:InvalidArgument',...
                                      'Each cell entry in opt.neumann must be a struct containing a ''f'' and a ''idx'' field.');
                            end
                            if isnumeric(opt.neumann{k}.f) && isscalar(opt.neumann{k}.f)
                                val = opt.neumann{k}.f;
                                opt.neumann{k}.f = @(X,N) ofem.matrixarray(val*ones(1,1,size(X,3)));
                            elseif isa(opt.neumann{k}.f,'function_handle')
                            else
                                error('ofem:elliptic:InvalidArgument',...
                                      'The ''f'' entry in opt.neumann must either be a scalar or a function handle.');
                            end
                        end
                    elseif isstruct(opt.neumann) && all(isfield(opt.neumann,{'f','idx'}))
                        neumann_f   = opt.neumann.f  ;
                        neumann_idx = opt.neumann.idx;
                        
                        if ~isvector(neumann_idx)
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''idx'' entry in opt.neumann must be a vector.');
                        end
                        
                        if isnumeric(neumann_f) && isscalar(neumann_f)
                            val       = neumann_f;
                            neumann_f = @(X,N) ofem.matrixarray(val*ones(1,1,size(X,3)));
                        elseif isa(neumann_f,'function_handle')
                        else
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''f'' entry in opt.neumann must either be a scalar or a function handle.');
                        end
                        
                        opt.neumann = cell(numel(neumann_idx),1);
                        for k=1:numel(neumann_idx)
                            opt.neumann{k}.f   = neumann_f;
                            opt.neumann{k}.idx = neumann_idx(k);
                        end
                    else
                        error('ofem:elliptic:InvalidArgument',...
                              'opt.neumann must either be a cell array or a structure containing a ''f'' and a ''idx'' field.');
                    end

                    Nneu        = numel(opt.neumann);
                    aux.neumann = cell(Nneu,1);
                end

                %% Robin boundary,
                if ~isfield(opt,'robin')
                    opt.robin={};
                    Nro=0;
                else
                    if iscell(opt.robin)
                        for k=1:numel(opt.robin)
                            if ~all(isfield(opt.robin{k},{'alpha','f','idx'}))
                                error('ofem:elliptic:InvalidArgument',...
                                      'Each cell entry in opt.robin must be a struct containing a ''alpha'', a ''f'' and a ''idx'' field.');
                            end
                            if isnumeric(opt.robin{k}.alpha) && isscalar(opt.robin{k}.alpha)
                                val = opt.robin{k}.alpha;
                                opt.robin{k}.alpha = @(X,N) ofem.matrixarray(val*ones(1,1,size(X,3)));
                            elseif isa(opt.robin{k}.alpha,'function_handle')
                            else
                                error('ofem:elliptic:InvalidArgument',...
                                      'The ''alpha'' entry in opt.robin must either be a scalar or a function handle.');
                            end
                            if isnumeric(opt.robin{k}.f) && isscalar(opt.robin{k}.f)
                                val = opt.robin{k}.f;
                                opt.robin{k}.f = @(X,N) ofem.matrixarray(val*ones(1,1,size(X,3)));
                            elseif isa(opt.robin{k}.f,'function_handle')
                            else
                                error('ofem:elliptic:InvalidArgument',...
                                      'The ''f'' entry in opt.robin must either be a scalar or a function handle.');
                            end
                        end
                    elseif isstruct(opt.robin) && all(isfield(opt.robin,{'alpha','f','idx'}))
                        robin_alpha = opt.robin.alpha;
                        robin_f     = opt.robin.f;
                        robin_idx   = opt.robin.idx ;
                        
                        if ~isvector(robin_idx)
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''idx'' entry in opt.robin must be a vector.');
                        end
                        if isnumeric(robin_alpha) && isscalar(robin_alpha)
                            val = robin_alpha;
                            robin_alpha = @(X,N) ofem.matrixarray(val*ones(1,1,size(X,3)));
                        elseif isa(robin_alpha,'function_handle')
                        else
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''alpha'' entry in opt.robin must either be a scalar or a function handle.');
                        end
                        if isnumeric(robin_f) && isscalar(robin_f)
                            val = robin_f;
                            robin_f = @(X,N) ofem.matrixarray(val*ones(1,1,size(X,3)));
                        elseif isa(robin_f,'function_handle')
                        else
                            error('ofem:elliptic:InvalidArgument',...
                                  'The ''f'' entry in opt.robin must either be a scalar or a function handle.');
                        end
                        
                        opt.robin = cell(numel(robin_idx),1);
                        for k=1:numel(robin_idx)
                            opt.robin{k}.alpha = robin_alpha;
                            opt.robin{k}.f     = robin_f;
                            opt.robin{k}.idx   = robin_idx(k);
                        end
                    else
                        error('ofem:elliptic:InvalidArgument',...
                              'opt.robin must either be a cell array or a structure containing a ''alpha'', a ''f'' and a ''idx'' field.');
                    end

                    Nro       = numel(opt.robin);
                    aux.robin = cell(Nro,1);
                end
            end


            if opt.S||opt.D||opt.M||~isempty(opt.force)
                intvol=1;
            end

            if ~isempty(opt.neumann) || ~isempty(opt.robin)
                intface=1;
            end

            if ~isempty(opt.dirichlet)
                intdiri=1;
            end

            if ~(intvol==1||intface==1||intdiri==1)
                warning('Requested to compute nothing!');
            end

            S=sparse(Nc,Nc);
            D=sparse(Nc,Nc);
            M=sparse(Nc,Nc);
			L=sparse(obj.mesh.Nco,obj.mesh.Nco);
			G=sparse(obj.mesh.Nco,Nc);
            M_robin=sparse(Nc,Nc);
            b=sparse(Nc,1);
            dirichlet=sparse(Nc,1);

%             opt.A=1;
%             opt.b=ones(3,1);
%             opt.c=1;

            %% start assembling
            tic;

            %% volume related integration
            if intvol==1
                % volume quad data
				[w,l] = obj.fe.quaddata(3,3);
                %[w,l] = obj.qr.data(0);

                % shape functions related stuff
                %pipj  = obj.fe.phiiphij(obj.mesh.dim);
                %phi   = obj.fe.phi(l);
                %dphi  = obj.fe.dphi(l);
				[phi,dphi] = obj.fe.basis(3);
				if opt.R
					[wLG,lLG] = obj.qrLG.data(0);
					dphiLG = obj.feLG.dphi(lLG);
					pipj = obj.feLG.phiiphij(obj.mesh.dim);
				end
                [DinvT,detD,Dk] = obj.mesh.jacobiandata;
                %detD = abs(detD);
                aux.detD    = detD;
                aux.Dk      = Dk;
                aux.DinvT   = DinvT;
                sign = reshape(obj.mesh.el2edsign',1,6,[]);
				sign = [sign,reshape(obj.mesh.el2fasign',1,4,[])];
                sign = repelem(sign,3,2,1);
                sign = ofem.matrixarray(sign);

                % perform assembly
                for i=1:Np
                    pIdx     = obj.mesh.parts{3,i};
                    elemsLoc = obj.mesh.el(pIdx,:);
                    detDLoc  = detD(:,:,pIdx);
                    DinvTLoc = DinvT(:,:,pIdx);
                    DkLoc    = Dk(:,:,pIdx);
                    signLoc  = sign(:,:,pIdx);
                    el2edLoc = obj.mesh.el2ed(pIdx,:);
					el2faLoc = obj.mesh.el2fa(pIdx,:);
                    
                    %% handle stiffness matrix
                    if opt.S==1
                        if iscell(opt.A)
                            aux.S{i} = obj.stiffness(opt.A{i},signLoc,DkLoc,detDLoc,dphi,elemsLoc,obj.mesh.ed,obj.mesh.fa,el2edLoc,el2faLoc,w,l,obj.mesh.co);
                        else
                            aux.S{i} = obj.stiffness(opt.A,signLoc,DkLoc,detDLoc,dphi,elemsLoc,obj.mesh.ed,obj.mesh.fa,el2edLoc,el2faLoc,w,l,obj.mesh.co)
                        end
                        S = S + aux.S{i};
                    end
                    %% handle damping matrix
                    if opt.D==1
                        if iscell(opt.b)
                            aux.D{i} = obj.damping(opt.b{i},opt.v{i},signLoc,detDLoc,DinvTLoc,DkLoc,phi,dphi,w,elemsLoc,obj.mesh.ed,el2edLoc);
                        else
                            aux.D{i} = obj.damping(opt.b,opt.v{i},signLoc,detDLoc,DinvTLoc,DkLoc,phi,dphi,w,elemsLoc,obj.mesh.ed,el2edLoc);
                        end
                        D = D + aux.D{i};
                    end
                    %% handle mass matrix
                    if opt.M==1
                        if iscell(opt.c)
                            aux.M{i} = obj.mass(opt.c{i},signLoc,DinvTLoc,detDLoc,phi,w,elemsLoc,obj.mesh.ed,el2edLoc,obj.mesh.co);
                        else
                            aux.M{i} = obj.mass(opt.c,signLoc,DinvTLoc,detDLoc,phi,w,elemsLoc,obj.mesh.ed,el2edLoc,obj.mesh.co);
                        end
                        M = M + aux.M{i};
					end
					%% handle lorenz gauge
					if opt.R==1
						[aux.G{i},aux.L{i}] = obj.lorenzGauge(opt.chi,opt.eps,signLoc,detDLoc,DinvTLoc,pipj,dphiLG,phi,wLG,w,obj.mesh.co,obj.mesh.ed,elemsLoc,el2edLoc);
						G = G + aux.G{i};
						L = L + aux.L{i};
					end
                    %% handle volume force matrix
                    if ~isempty(opt.force)
                        if iscell(opt.force)
                            aux.force{i} = obj.volume_force(signLoc,detDLoc,DinvTLoc,phi,w,l,opt.force{i},elemsLoc,obj.mesh.co,el2edLoc,pIdx,Nc);
                        else
                            aux.force{i} = obj.volume_force(signLoc,detDLoc,DinvTLoc,phi,w,l,opt.force,elemsLoc,obj.mesh.co,el2edLoc,pIdx,Nc);
                        end
                        b = b + aux.force{i};
                    end 
				end
            end

            %% surface related integration
            if intface==1
                % surface quad data
                [w,l] = obj.qr.data(1);
                phi   = obj.fe.phi(l);
                pipj  = obj.fe.phiiphij(obj.mesh.dim-1);

                for i=1:Nneu
                    [meas,faces,~] = obj.mesh.neumann(opt.neumann{i}.idx);
                    aux.neumann{i} = obj.pressure(meas{1},phi,w,l,opt.neumann{i}.f,faces{1},obj.mesh.co);
                    b = b + aux.neumann{i};
                end

                for i=1:Nro
                    [meas,faces,~] = obj.mesh.neumann(opt.robin{i}.idx);
                    aux.robin{i}   = obj.pressure(meas{1},phi,w,l,opt.robin{i}.f,faces{1},obj.mesh.co);
%                     aux.M_robin{i} = obj.mass(opt.robin{i}.alpha(1),meas{1},phi,w,l,faces{1},obj.mesh.co);
                    aux.M_robin{i} = obj.mass(opt.robin{i}.alpha(1),meas{1},pipj,faces{1},obj.mesh.co);
                    M_robin        = M_robin + aux.M_robin{i};
                    b = b + aux.robin{i};
                end
            end

            %% Dirichlet data
            %DOFs = 1:Nc; % NOTE: this is only valid for P1 elements => need an update
			DOFs = 1:(2*size(obj.mesh.el,1)+2*size(obj.mesh.fa,1));
            if intdiri==1
                for i=1:Ndiri
                    edges = obj.mesh.dirichletEdges(opt.dirichlet{i}.idx);
                    aux.dirichletEdges{i}=edges{1};
                    DOFs  = setdiff(DOFs,edges{1});
                    aux.dirichlet{i} = obj.dirichlet(opt.dirichlet{i}.f,edges{1},obj.mesh.ed,obj.mesh.co);
                    dirichlet = dirichlet+aux.dirichlet{i};
                    b = b - (S+D+M+M_robin)*aux.dirichlet{i};
                end
            end
            asm.DOFs = DOFs;

            if opt.S
                asm.S=S;
            end
            if opt.D
                asm.D=D;
            end
            if opt.M
                asm.M=M;
			end
			if opt.R
				asm.G=G;
				asm.L=L;
			end
            if ~isempty(opt.force) || ~isempty(opt.dirichlet) || ~isempty(opt.neumann) || ~isempty(opt.robin)
                asm.b=b;
            end

            if ~isempty(opt.robin)
                asm.M_robin = M_robin;
            end

            if ~isempty(opt.dirichlet)
                asm.dirichlet = dirichlet;
            end


            %% info variable
            info.time2assemble = toc;
        end
        
            

        %%
        function grad=gradu(obj,u)
        %GRADU computes the gradient at DOFs.
        %
        % grad=gradu(u) computes the gradient grad of the FEM solution u at
        % DOFs. grad is a Ndofs by Nd matrix, where Ndofs are the number of
        % nodes and Nd the dimension of the spatial space.
        %
        
        switch obj.fe
            case ofem.finiteelement.P1
                
                switch obj.mesh.dim
                    case 2
                        % d denotes the dimension of polynomial space,
                        % i.e. for P1 elements it is 1
                        d=1;             % degree of finite element space
                        m=(d+2)*(d+3)/2; % polynomial degree of approximant

                        Ndof = size(obj.mesh.co,3);
                        
                        % statistics and machine learning toolbox
                        co = double(squeeze(obj.mesh.co))';
                        I  = obj.mesh.el(:,[1 1 2 2 3 3]);
                        J  = obj.mesh.el(:,[2 3 1 3 1 2]);
                        h  = co(I,:)-co(J,:); h=sqrt(dot(h,h,2));
                        h  = accumarray(I(:),h(:),[],@max,[],true);
                        ht = full(h);
                        D  = pdist2(co,co);
                        while 1
                            idx  = D<repmat(ht,1,Ndof);
                            idx2 = sum(idx,2)<m;
                            if ~any(idx2)
                                break;
                            end
                            ht(idx2)=ht(idx2)+h(idx2);
                        end
                        clear I J idx2 maxR maxRt D;

                        ui_r=zeros(6,1,Ndof);
                        for i=1:Ndof
                            idxl=find(idx(i,:));
                            ui = u (idxl  );
                            xi = co(idxl,1);
                            yi = co(idxl,2);

                            A  = [ones(numel(idxl),1), xi, yi, xi.*yi, xi.^2, yi.^2];

                            ui_r(:,:,i) = A\ui;
                        end

%                         n=(d+3)*(d+4)/2; % degree of point considering for least-squares
%                         co_idx = knnsearch(co,co,'K',n)';
% 
%                         ui = reshape(u (co_idx(:)  ),n,1,[]);
%                         xi = reshape(co(co_idx(:),1),n,1,[]);
%                         yi = reshape(co(co_idx(:),2),n,1,[]);
%                         
%                         clear co_idx;
% 
%                         A = [ones(n,1,Ndof), xi, yi, xi.*yi, xi.^2, yi.^2];
% 
%                         ui_r=zeros(6,1,Ndof);
%                         for i=1:Ndof
%                             ui_r(:,:,i) = A(:,:,i)\ui(:,:,i);
%                         end

                        x = obj.mesh.co(1,:,:);
                        y = obj.mesh.co(2,:,:);

                        grad = [ ui_r(2,:,:)+ui_r(4,:,:).*y+2*ui_r(5,:,:).*x, ...
                                 ui_r(3,:,:)+ui_r(4,:,:).*x+2*ui_r(6,:,:).*y ];

                        grad = reshape(grad,2,[])';

%                         ui_r = cellfun(@(A,b) A\b      , ...
%                             mat2cell(A ,n*ones(1,Ndof),m), ...
%                             mat2cell(ui,n*ones(1,Ndof),1), ...
%                             'UniformOutput',false);
%                         ui_r = reshape(cell2mat(ui_r),m,[])';
%                         
%                         clear A;
%                         
%                         x = co(:,1);
%                         y = co(:,2);
%                         
%                         grad = [ ui_r(:,2)+ui_r(:,4).*y+2*ui_r(:,5).*x, ...
%                                  ui_r(:,3)+ui_r(:,4).*x+2*ui_r(:,6).*y ];
                        
                    case 3
                        % d denotes the dimension of polynomial space,
                        % i.e. for P1 elements it is 1
                        %d=1;             % degree of finite element space
                        %m=(d+2)*(d+3)/2; % polynomial degree of approximant
                        m = 10;
                        % n=(d+3)*(d+4)/2; % degree of point considering for least-squares
                        n = 3*m;
                        
                        % statistics and machine learning toolbox
                       
                        co_idx = knnsearch(squeeze(obj.mesh.co)',squeeze(obj.mesh.co)','K',n)';
                        
                        %                 ui = u (co_idx(:)  );
                        %                 xi = co(co_idx(:),1);
                        %                 yi = co(co_idx(:),2);
                        %                 zi = co(co_idx(:),3);
                        
                        
                        
                        
                        ui = u(co_idx(:));
                        xi = squeeze(obj.mesh.co(1, :, co_idx(:)));
                        yi = squeeze(obj.mesh.co(2, :, co_idx(:)));
                        zi = squeeze(obj.mesh.co(3, :, co_idx(:)));
                        
                        
                        
                        clear co_idx;
                        
                        Ndof = size(obj.mesh.co,3);
                        
                        A = [ones(Ndof*n,1), xi, yi, zi, xi.*yi ,xi.*zi, yi.*zi, xi.^2, yi.^2, zi.^2];
                        
                        ui_r = cellfun(@(A,b) A\b      , ...
                            mat2cell(A ,n*ones(1,Ndof),m), ...
                            mat2cell(ui,n*ones(1,Ndof),1), ...
                            'UniformOutput',false);
                        ui_r = reshape(cell2mat(ui_r),m,[])';
                        
                        clear A;
                        
                        x = squeeze(obj.mesh.co(1, :,:));
                        y = squeeze(obj.mesh.co(2,:, :));
                        z = squeeze(obj.mesh.co(3, :,:));
                        
                        grad = [ ui_r(:,2)+ui_r(:,5).*y+ui_r(:,6).*z+2*ui_r(:, 8).*x, ...
                                 ui_r(:,3)+ui_r(:,5).*x+ui_r(:,7).*z+2*ui_r(:, 9).*y,...
                                 ui_r(:,4)+ui_r(:,6).*x+ui_r(:,7).*y+2*ui_r(:,10).*z];
                        
                        
                        % warning('3D gradient recovery not implemented yet!');
                end
            otherwise
                error('ofem:elliptic:NotSupported',...
                      'Reconstruction of P2 gradient not implemented, yet!');
        end
        end
        
        function gradi = gradq (obj, u, xq)
        %GRADQ computes the gradient at a query point.
        %
        % grad=gradq(u, xq) computes the gradient grad of the FEM solution u at
        % a query point xq. gradi is a Nxq by Nd matrix, where Nxq is the number of
        % query points and Nd the dimension of the spatial space.
            

        switch obj.fe
            case ofem.finiteelement.P1
                
                switch obj.mesh.dim
                    case 2
                        warning('2D query point gradient recovery not implemented yet!');
                        
                    case 3
                        % d denotes the dimension of polynomial space,
                        % i.e. for P1 elements it is 1
                        %d=1;             % degree of finite element space
                        %m=(d+2)*(d+3)/2; % polynomial degree of approximant
                        m = 10;
                        % n=(d+3)*(d+4)/2; % degree of point considering for least-squares
                        n = 3*m;
                        
                          

                        co_idx = knnsearch(squeeze(obj.mesh.co)',xq,'K',n)';

                        ui = u(co_idx(:));
                        xi = squeeze(obj.mesh.co(1, :, co_idx(:)));
                        yi = squeeze(obj.mesh.co(2, :, co_idx(:)));
                        zi = squeeze(obj.mesh.co(3, :, co_idx(:)));

                        clear co_idx;

                        Ndof = size(xq,1);

                        A = [ones(Ndof*n,1), xi, yi, zi, xi.*yi ,xi.*zi, yi.*zi, xi.^2, yi.^2, zi.^2];

                        ui_r = cellfun(@(A,b) A\b      , ...
                            mat2cell(A ,n*ones(1,Ndof),m), ...
                            mat2cell(ui,n*ones(1,Ndof),1), ...
                            'UniformOutput',false);
                        ui_r = reshape(cell2mat(ui_r),m,[])';

                        clear A;

                        x = xq(:,1);
                        y = xq(:,1);
                        z = xq(:,1);

                        gradi= [ ui_r(:,2)+ui_r(:,5).*y+ui_r(:,6).*z+2*ui_r(:, 8).*x, ...
                                 ui_r(:,3)+ui_r(:,5).*x+ui_r(:,7).*z+2*ui_r(:, 9).*y,...
                                 ui_r(:,4)+ui_r(:,6).*x+ui_r(:,7).*y+2*ui_r(:,10).*z];
                end
            otherwise
                error('ofem:elliptic:NotSupported',...
                      'Reconstruction of P2 gradient not implemented, yet!');
        end
        end


        %%
        function h=plot(obj,u,varargin)
        %PLOT plots the solution.
        %
        co = double(squeeze(obj.mesh.co)');

        name = 'u';
        if nargin==3
            if ~ischar(varargin{1})
                warning('ofem:elliptic:InvalidArgument',...
                        'Optional argument must be a valid string!');
            else
                name=varargin{1};
            end
        end

        switch obj.mesh.dim
            case 2
                h=trimesh(obj.mesh.el          , ...
                          co(:,1)              , ...
                          co(:,2)              , ...
                          u                    , ...
                          'FaceColor', 'interp', ...
                          'EdgeColor', 'none'  );
                xlabel('x-axis');
                ylabel('y-axis');
                zlabel(name);
                colorbar;

            case 3
                h=tetramesh(obj.mesh.el, ...
                            co         , ...
                            u          , ...
                            'FaceColor', 'interp', ...
                            'EdgeColor', 'none'  );
                xlabel('x-axis');
                ylabel('y-axis');
                zlabel('z-axis');
                legend(name);
                colorbar;
        end
        end
        
                %% Reconstruct the solution at the nodes from nedelec computations
        function uNode = edge2NodeData(obj,u)
%             [w,l] = obj.qr.data(0);
            [DinvT,detD,Dk] = obj.mesh.jacobiandata();
            l = [1/4;1/4;1/4];
            detD = abs(detD);
            phi = obj.fe.phi(l);
            u = u(obj.mesh.el2ed);
            u = u.*double(obj.mesh.el2edsign);
            u = reshape(u',6,1,[]);
            u = ofem.matrixarray(u);
            uElem = detD*(DinvT*phi*u);
            uElem = reshape(uElem(:),3,[]);
            uElem = repelem(uElem,1,4);
            detD = detD(:);
            detD = repelem(detD,4,1);
            i = obj.mesh.el;
            i = i*3;
            i = repelem(i,1,3);
            vect = [-2,-1,0];
            vect = repmat(vect,1,4);
            i = i+vect;
            i = i';
            j = obj.mesh.el';
            uNodes2 = sparse(i(:),1,uElem(:));
            detDscale2 = sparse(j(:),1,detD);
            uNodes2 = reshape(full(uNodes2),3,1,[]);
            uNodes2 = ofem.matrixarray(uNodes2);
            detDscale2 = reshape(full(detDscale2),1,1,[]);
            detDscale2 = ofem.matrixarray(detDscale2);
            uNode = uNodes2*(1./detDscale2);
        end
        
        %% 
        function uCell = edge2CellData(obj,u)
            % Reconstruct cell data from the solution
            [DinvT,~,~] = obj.mesh.jacobiandata();
            uElem = u(obj.mesh.el2ed(:,:));
            uElem = ofem.matrixarray(reshape(uElem',size(uElem,2),1,[]));
            sign = reshape(obj.mesh.el2edsign',1,6,[]);
            sign = repmat(sign,3,1,1);
            sign = ofem.matrixarray(sign);
            l = [1/4;1/4;1/4];
            phi = obj.fe.phi(l);
            uCell = (DinvT*(phi.*sign))*uElem;
        end
        
        %% 
        function uCell = edge2CellCurl(obj,u)
            % Compute the Curl of the solution
            [~,detD,Dk] = obj.mesh.jacobiandata();
            dphi = obj.fe.dphi([1/4;1/4;1/4]);
            uElem = u(obj.mesh.el2ed(:,:));
            uElem = ofem.matrixarray(reshape(uElem',size(uElem,2),1,[]));
            sign = reshape(obj.mesh.el2edsign',1,6,[]);
            sign = repmat(sign,3,1,1);
            sign = ofem.matrixarray(sign);
            uCell = (1./detD)*(Dk*(dphi.*sign))*uElem;
        end
        
        %%
        function u0 = initialData(obj,f)
            v = obj.mesh.co(:,:,obj.mesh.ed(:,2))-obj.mesh.co(:,:,obj.mesh.ed(:,1));

            co = 1/2*obj.mesh.co(:,:,obj.mesh.ed(:,1))+1/2*obj.mesh.co(:,:,obj.mesh.ed(2));

            F = f(co);

            u0 = squeeze(dot(F,v));
        end
        
        function [a0,eID] = setExcitation(obj,roi)
            ss = obj.mesh.roi(2,roi.idx);
            ss = ss{1};
            ss = unique(sort(ss,2),'rows','legacy');
            ss = [ss(:,1),ss(:,2);ss(:,1),ss(:,3);ss(:,2),ss(:,3)];
            idx = ismember(obj.mesh.ed,ss,'rows');
            eID = find(idx);
            v = obj.mesh.co(:,:,obj.mesh.ed(eID,2))-obj.mesh.co(:,:,obj.mesh.ed(eID,1));

            co = 1/2*obj.mesh.co(:,:,obj.mesh.ed(eID,1))+1/2*obj.mesh.co(:,:,obj.mesh.ed(eID,2));
            
            F = roi.f(co);
            
            a0 = double(squeeze(dot(F,v)));
        end
            
    end
end


















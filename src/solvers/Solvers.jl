export ExplicitSolver, NewmarkSolver, StaticSolver

@doc """
Central Difference Explicit solver for Ma + fint = fext
    a, v, u are acceleration, velocity and displacement

    u_{n+1} = u_n + dtv_n + dt^2/2 a_n
    v_{n+1} = v_n + dt/2(a_n + a_{n+1})

    M a_{n+1} + C v_{n+1} + R(u_{n+1}) = P_{n+1}
    (M + dt/2 C) a_{n+1} = P_{n+1} - R(u_{n+1}) - C(v_n + dt/2 a_{n})


    Alternative, todo:
    M a_n + C v_n + R(u_n) = P_n
    M(u_{n+1} - 2u_n + u_{n-1}) + dt/2*C(u_{n+1} - u_{n-1}) + dt^2 R(u_n) = dt^2 P_n
    (M + dt/2 C) u_{n+1} = dt^2(P_n - R(u_n) + dt/2 C u_{n-1} + M(2u_n - u_{n-1})

    For the first step
    u_{-1} = u_0 - dt*v_0 + dt^2/2 a_0
    a_0 = M^{-1}(-Cv_0 - R(u_0) + P_0)
"""->
function ExplicitSolver(Δt, globdat, domain)
    state = globdat.state
    velo = globdat.velo
    acce = globdat.acce

    fext = domain.fext
    
    velo += 0.5*Δt * acce
    state += Δt * velo
    
    fint  = assembleInternalForce( globdat, domain, Δt)

    if length(globdat.M)==0
        error("globalDat is not initialized, call `assembleMassMatrix!(globaldat, domain)`")
    end

    acce = (fext-fint)./globdat.Mlumped
    velo += 0.5 * Δt * acce
    globdat.acce[:] = acce[:]

    globdat.time  += Δt
    # globdat.elements.commitHistory()
end





# @doc """
#     Implicit solver for Ma + C v + R(u) = P
#     a, v, u are acceleration, velocity and displacement

#     u_{n+1} = u_n + dtv_n + dt^2/2 ((1 - 2\beta)a_n + 2\beta a_{n+1})
#     v_{n+1} = v_n + dt((1 - gamma)a_n + gamma a_{n+1})

#     M a_{n+0.5} + fint(u_{n+0.f}) = fext_{n+0.5}
#
#     absolution error ε = 1e-8, 
#     relative error ε0 = 1e-8   
# """->

function NewmarkSolver(Δt, globdat, domain, αm = -1.0, αf = 0.0, ε = 1e-8, ε0 = 1e-8, maxiterstep=100, η = 1.0)
    local res0
    # @info maxiterstep
    # error()
    #@info NewmarkSolver
    
    β2 = 0.5*(1 - αm + αf)^2
    γ = 0.5 - αm + αf

    # compute solution at uⁿ⁺¹
    globdat.time  += (1 - αf)*Δt

    # domain.Dstate = uⁿ
    domain.Dstate = domain.state[:]
    updateDomainStateBoundary!(domain, globdat)
    
    M = globdat.M
    
    ∂∂u = globdat.acce[:] #∂∂uⁿ
    u = globdat.state[:]  #uⁿ
    ∂u  = globdat.velo[:] #∂uⁿ

    
    fext = getExternalForce!(domain, globdat)


    ∂∂up = ∂∂u[:]

    Newtoniterstep, Newtonconverge = 0, false

    norm0 = Inf

    # @show "start Newton u ", u
    # @show "start Newton du ", ∂u
    # @show "start Newton ddu ", ∂∂u

    while !Newtonconverge
        
        Newtoniterstep += 1
        
        domain.state[domain.eq_to_dof] = (1 - αf)*(u + Δt*∂u + 0.5 * Δt * Δt * ((1 - β2)*∂∂u + β2*∂∂up)) + αf*u

        fint, stiff = assembleStiffAndForce( globdat, domain, Δt)

        # error()
        res = M * (∂∂up *(1 - αm) + αm*∂∂u)  + fint - fext
        # @show fint, fext
        if Newtoniterstep==1
            res0 = res 
        end

        A = M*(1 - αm) + (1 - αf) * 0.5 * β2 * Δt^2 * stiff
        
        Δ∂∂u = A\res

        #@info " norm(Δ∂∂u) ", norm(Δ∂∂u) 
        while η * norm(Δ∂∂u) > norm0
            η /= 2.0
            @info "η", η
        end
            


        ∂∂up -= η*Δ∂∂u

        # @show norm(A*Δ∂∂u-res)
        # r, B = f(∂∂u)
        # #@show norm(res), norm(r), norm(B)
        # error()
        # #@show Δ∂∂u
        # if globdat.time>0.0001
        #     function f(∂∂up)
        #         domain.state[domain.eq_to_dof] = (1 - αf)*(u + Δt*∂u + 0.5 * Δt * Δt * ((1 - β2)*∂∂u + β2*∂∂up)) + αf*u
        #         fint, stiff = assembleStiffAndForce( globdat, domain )
        #         fint, (1 - αf) * 0.5 * β2 * Δt^2 * stiff
        #     end
        #     gradtest(f, ∂∂up)
        #     error()
        # end
        println("$Newtoniterstep/$maxiterstep, $(norm(res))")
        if (norm(res)< ε || norm(res)< ε0*norm(res0) ||Newtoniterstep > maxiterstep)
            if Newtoniterstep > maxiterstep
                function f(∂∂up)
                    domain.state[domain.eq_to_dof] = (1 - αf)*(u + Δt*∂u + 0.5 * Δt * Δt * ((1 - β2)*∂∂u + β2*∂∂up)) + αf*u
                    fint, stiff = assembleStiffAndForce( globdat, domain )
                    fint, (1 - αf) * 0.5 * β2 * Δt^2 * stiff
                end
                gradtest(f, ∂∂up)
                # error()
                @warn("Newton iteration cannot converge $(norm(res))"); Newtonconverge = true
            else
                Newtonconverge = true
                printstyled("[Newmark] Newton converged $Newtoniterstep\n", color=:green)
            end
        end

        η = min(1.0, 2η)
        norm0 = norm(Δ∂∂u)
        # println("================ time = $(globdat.time) $Newtoniterstep =================")
    end
    


    globdat.Dstate = globdat.state[:]
    globdat.state += Δt * ∂u + Δt^2/2 * ((1 - β2) * ∂∂u + β2 * ∂∂up)

    
    globdat.velo += Δt * ((1 - γ) * ∂∂u + γ * ∂∂up)
    globdat.acce = ∂∂up[:]

   
    globdat.time  += αf*Δt
    #@info "After Newmark, at T = ", globdat.time, " the disp is ", domain.state
    commitHistory(domain)
    updateStates!(domain, globdat)

    
    

    fint, stiff = assembleStiffAndForce( globdat, domain, Δt)
    push!(domain.history["fint"], fint)
    push!(domain.history["fext"], fext)
    
end 


@doc """
    Implicit solver for fint(u) = fext
    u is the displacement
    Newton iteration, with time-stepping at P
    u_{n+1} = u_n -  dR(u)^{-1} *(R(u) - P)

    :param app:
    :param u_0:
    :return: u_{oo}
"""->
function StaticSolver(globdat, domain, loaditerstep = 10, ε = 1.e-8, maxiterstep=100)
    
    fext = domain.fext
    globdat.Dstate = copy(globdat.state)
    for iterstep = 1:loaditerstep

        # Newton's method
        Newtoniterstep, Newtonconverge = 0, false
        
        while  !Newtonconverge

            Newtoniterstep += 1
            
            fint, stiff = assembleStiffAndForce( globdat, domain )
            # #@show "fint", fint, "stiff", stiff
            # #@show "fext", fext
       
            res = fint - iterstep/loaditerstep * fext

            Δstate = stiff\res

            globdat.state -= Δstate
            #@show Newtoniterstep, norm(res)
            if (norm(res) < ε  || Newtoniterstep > maxiterstep)
                if Newtoniterstep > maxiterstep
                    @error "$Newtoniterstep Newton iteration cannot converge"
                end
                Newtonconverge = true
            end
            updateStates!(domain, globdat)
        end
        commitHistory(domain)
        globdat.Dstate = copy(globdat.state)
    end
end

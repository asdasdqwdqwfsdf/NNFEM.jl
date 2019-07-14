export DynamicMatLawLoss, BFGS, preprocessing, ADAM, NNMatLaw

@doc """
    form the loss function, based on dynamic equilibrium 
        (Mddu + fint(NN, E, DE) + MIDddu_bc = fext

    loss = ∑ ||fint(NN, E, DE) - (fext - MIDddu_bc - Mddu)||^2
"""->
function DynamicMatLawLoss(domain::Domain, E_all::Array{Float64}, fext::Array{Float64},
        nn::Function)
    # define variables
    neles = domain.neles
    nGauss = length(domain.elements[1].weights)
    nstrains = 3
    NT = size(E_all,1)-1
    @assert size(E_all)==(NT+1, neles*nGauss, nstrains)
    @assert size(fext)==(NT, domain.neqs)
    # @show E_all[2,:,:]
    E_all = constant(E_all)
    fext = constant(fext)

    function cond0(i, ta_loss, ta_σ)
        i<=NT+1
    end

    function body(i, ta_loss, ta_σ)
        σ0 = read(ta_σ, i-1)
        E = E_all[i]
        DE = E_all[i-1]
        # @show E, DE
        fint, σ = tfAssembleInternalForce(domain,nn,E,DE,σ0)
        # # @show E, DE
        # op = tf.print(i,(fint), summarize=-1)
        # fint = bind(fint, op)

        ta_σ = write(ta_σ, i, σ)
        ta_loss = write(ta_loss, i, sum((fint-fext[i-1])^2))
        i+1, ta_loss, ta_σ
    end

    σ0 = constant(zeros(neles*nGauss, nstrains))
    ta_σ = TensorArray(NT+1); ta_σ = write(ta_σ, 1, σ0)
    ta_loss = TensorArray(NT+1); ta_loss = write(ta_loss, 1, constant(0.0))
    i = constant(2, dtype=Int32)
    _, out, _ = while_loop(cond0, body, [i,ta_loss, ta_σ]; parallel_iterations=1)
    total_loss = sum(stack(out)[2:NT])
    return total_loss
end

function BFGS(sess::PyObject, loss::PyObject, max_iter=15000; kwargs...)
    __cnt = 0
    function print_loss(l)
        if mod(__cnt,1)==0
            println("iter $__cnt, current loss=",l)
        end
        __cnt += 1
    end
    __iter = 0
    function step_callback(rk)
        if mod(__iter,1)==0
            println("================ ITER $__iter ===============")
        end
        __iter += 1
    end
    opt = ScipyOptimizerInterface(loss, method="L-BFGS-B",options=Dict("maxiter"=> max_iter, "ftol"=>1e-12, "gtol"=>1e-12))
    @info "Optimization starts..."
    ScipyOptimizerMinimize(sess, opt, loss_callback=print_loss, step_callback=step_callback, fetches=[loss])
end

function ADAM(sess::PyObject, loss::PyObject; kwargs...)
    opt = AdamOptimizer().minimize(loss)
    init(sess)
    for i = 1:10000
        l, _ = run(sess, [loss, opt])
        println("Iter $i, loss = $l")
    end
end

function NNMatLaw(sess::PyObject)
    vars = get_collection("nn")
    println(vars)
    vars = run(sess, vars)
    n = div(length(vars),2)
    for i = 1:n
        vars[2i] = repeat(reshape(vars[2i], 1, length(vars[2i])), size(vars[2(i-1)],1), 1)
    end
    function nn(ε, ε0, σ0, Δt)
        x = reshape([ε; ε0; σ0], 1, 9)
        for i = 1:n
            @show size(vars[2(i-1)+1]), size(vars[2i])
            x = x*vars[2(i-1)+1]+vars[2i]
            if i<=n-1
                x = tanh(x)
            end
            @show size(x)
        end
        return x
    end
    return nn
end

# compute E from U 
function preprocessing(domain::Domain, globdat::GlobalData, F::Array{Float64},Δt::Float64)
    U = hcat(domain.history["state"]...)
    # @info " U ", size(U),  U'
    M = globdat.M
    MID = globdat.MID 

    NT = size(U,2)-1
    @info NT
    @assert size(F,2)==NT+1

    bc_acc = zeros(sum(domain.EBC.==-2),NT)
    for i = 1:NT
        _, bc_acc[:,i]  = globdat.EBC_func(Δt*i)
    end
    @info bc_acc

    
    ∂∂U = zeros(size(U,1), NT+1)
    ∂∂U[:,2:NT] = (U[:,1:NT-1]+U[:,3:NT+1]-2U[:,2:NT])/Δt^2
    for i = 1:size(∂∂U,2)
        println("***$(∂∂U[:,i])")
    end
    # println("∂∂U, $(∂∂U)")
    fext = F[:,2:end]-M*∂∂U[domain.dof_to_eq,2:end]-MID*bc_acc
    
    neles = domain.neles
    nGauss = length(domain.elements[1].weights)
    neqns_per_elem = length(getEqns(domain,1))
    nstrains = 3
    E_all = zeros(NT+1, neles*nGauss, nstrains)

    for i = 1:NT+1
        domain.state = U[:, i]
        # @info "domain state", domain.state
        # Loop over the elements in the elementGroup to construct strain and geo-matrix E_all and w∂E∂u_all
        for iele  = 1:neles
            element = domain.elements[iele]

            # Get the element nodes
            el_nodes = getNodes(element)

            # Get the element nodes
            el_eqns = getEqns(domain,iele)

            el_dofs = getDofs(domain,iele)

            el_state  = getState(domain,el_dofs)

            # Get the element contribution by calling the specified action
            E, w∂E∂u = getStrain(element, el_state) 
            # @show E, nGauss
            E_all[i, (iele-1)*nGauss+1:iele*nGauss, :] = E
        end
    end
    # DEBUG
    fext = hcat(domain.history["fint"]...)
    return fext'|>Array, E_all
end
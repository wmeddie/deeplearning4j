/*-
 *
 *  * Copyright 2016 Skymind,Inc.
 *  *
 *  *    Licensed under the Apache License, Version 2.0 (the "License");
 *  *    you may not use this file except in compliance with the License.
 *  *    You may obtain a copy of the License at
 *  *
 *  *        http://www.apache.org/licenses/LICENSE-2.0
 *  *
 *  *    Unless required by applicable law or agreed to in writing, software
 *  *    distributed under the License is distributed on an "AS IS" BASIS,
 *  *    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  *    See the License for the specific language governing permissions and
 *  *    limitations under the License.
 *
 */
package org.deeplearning4j.arbiter.optimize.api.saving;

import org.deeplearning4j.arbiter.optimize.api.OptimizationResult;
import org.nd4j.shade.jackson.annotation.JsonInclude;
import org.nd4j.shade.jackson.annotation.JsonTypeInfo;

import java.io.IOException;
import java.util.List;

/**
 * The ResultSaver interface provides a means of saving models in such a way that they can be loaded back into memory later,
 * regardless of where/how they are saved.
 *
 * @author Alex Black
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonTypeInfo(use = JsonTypeInfo.Id.CLASS, include = JsonTypeInfo.As.PROPERTY, property = "@class")
public interface ResultSaver {

    /**
     * Save the model (including configuration and any additional evaluation/results)
     *
     * @param result Results to save
     * @return ResultReference, such that the result can be loadde back into memory
     * @throws IOException If IO error occurs during model saving
     */
    ResultReference saveModel(OptimizationResult result) throws IOException;

    /**
     * @return The candidate types supported by this class
     */
    List<Class<?>> getSupportedCandidateTypes();

    /**
     * @return The model types supported by this class
     */
    List<Class<?>> getSupportedModelTypes();


}
